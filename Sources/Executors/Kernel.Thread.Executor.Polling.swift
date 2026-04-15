//
//  Kernel.Thread.Executor.Polling.swift
//  swift-executors
//

#if !os(Windows)

extension Kernel.Thread.Executor {
    /// Single-thread executor whose wait primitive is a kernel event source.
    ///
    /// One OS thread, one job queue, one `Executor.Wait.Event.Source`. The run
    /// loop interleaves drain-jobs with a consumer-supplied tick body that polls
    /// and dispatches kernel events. Absorbs `IO.Event.Loop` and
    /// `IO.Completion.Loop` as data-plane consumers.
    ///
    /// ## Race Safety
    ///
    /// The tick body runs on the executor's own thread — the same thread that
    /// dispatches actor jobs. Domain state (registrations, entries, the source)
    /// is touched by a single thread. See research doc V5.
    ///
    /// ## Lifecycle
    /// Call `shutdownNow()` before deallocation.
    public final class Polling: SerialExecutor, TaskExecutor, @unchecked Sendable {
        /// Outcome returned from the tick body.
        public enum Outcome: Sendable {
            /// Continue the run loop.
            case `continue`
            /// Halt the run loop.
            case halt
        }

        private var jobs: Executor_Primitives.Executor.Job.Queue
        private var drainBuffer: Executor_Primitives.Executor.Job.Queue
        private let queueLock: Kernel.Thread.Mutex
        private var waitSource: Executor_Primitives.Executor.Wait.Event.Source
        private let _shutdown: Executor_Primitives.Executor.Shutdown.Flag
        private var threadHandle: Kernel.Thread.Handle?
        private let tick: @Sendable () -> Outcome

        /// Creates a polling executor.
        ///
        /// - Parameters:
        ///   - source: The kernel event source to poll. Consumed.
        ///   - tick: Called each iteration after draining pending jobs. The tick
        ///     body MUST include a blocking wait (typically via `withSource { $0.poll(...) }`)
        ///     — a non-blocking tick will busy-spin. Returns `.continue` to keep
        ///     running or `.halt` to stop. Runs on the executor's own thread.
        public init(
            source: consuming Kernel.Event.Source,
            tick: @escaping @Sendable () -> Outcome
        ) {
            self.jobs = .init()
            self.drainBuffer = .init()
            self.queueLock = .init()
            self.waitSource = .init(source: consume source)
            self._shutdown = .init()
            self.tick = tick
            self.threadHandle = unsafe Kernel.Thread.trap(Ownership.Transfer.Retained(self)) { retained in
                retained.take().runLoop()
            }
        }
    }
}

// MARK: - SerialExecutor

extension Kernel.Thread.Executor.Polling {
    public func enqueue(_ job: consuming ExecutorJob) {
        enqueue(UnownedJob(job))
    }

    public func enqueue(_ job: UnownedJob) {
        let runInline: Bool = queueLock.withLock {
            guard !_shutdown.isSet else { return true }
            jobs.enqueue(job)
            return false
        }
        if runInline {
            unsafe job.runSynchronously(on: asUnownedSerialExecutor())
        } else {
            waitSource.wakeup.wake()
        }
    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        unsafe UnownedSerialExecutor(ordinary: self)
    }
}

// MARK: - TaskExecutor

extension Kernel.Thread.Executor.Polling {
    public func asUnownedTaskExecutor() -> UnownedTaskExecutor {
        unsafe UnownedTaskExecutor(ordinary: self)
    }
}

// MARK: - Source Access

extension Kernel.Thread.Executor.Polling {
    /// Access the underlying event source for registration and configuration.
    public func withSource<R>(_ body: (inout Kernel.Event.Source) -> R) -> R {
        waitSource.withSource(body)
    }
}

// MARK: - Shutdown

extension Kernel.Thread.Executor.Polling {
    /// Signal the run loop to halt and join the thread.
    public func shutdownNow() {
        _shutdown.set()
        waitSource.wakeup.wake()
        threadHandle.take()?.join()
    }
}

// MARK: - Run Loop

extension Kernel.Thread.Executor.Polling {
    private func runLoop() {
        while !_shutdown.isSet {
            drainJobs()
            if _shutdown.isSet { break }
            if case .halt = tick() { _shutdown.set(); break }
        }
        drainJobs()
    }

    private func drainJobs() {
        while true {
            queueLock.withLock { jobs.drain(into: &drainBuffer) }
            guard !drainBuffer.isEmpty else { return }
            while let job = drainBuffer.dequeue() {
                unsafe job.runSynchronously(on: asUnownedSerialExecutor())
            }
        }
    }
}

#endif
