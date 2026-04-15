//
//  Kernel.Thread.Executor.Polling.swift
//  swift-executors
//

// WHY: #if !os(Windows) — Kernel.Event.Source requires epoll (Linux) or
// kqueue (Darwin), neither available on Windows. A future
// Kernel.Thread.Executor.IOCP sibling will serve the Windows role.
// TRACKING: executor-package-design.md Decision #6.
#if !os(Windows)

extension Kernel.Thread.Executor {
    /// Single-thread executor whose wait primitive is a kernel event source.
    ///
    /// One OS thread, one job queue, one `Executor.Wait.Event.Source`. The run
    /// loop interleaves drain-jobs with a blocking poll on the event source,
    /// then passes received events to a consumer-supplied tick body.
    ///
    /// ## Event Flow
    ///
    /// ```
    /// drain jobs → poll (blocking) → tick(events) → repeat
    /// ```
    ///
    /// The run loop blocks in `waitSource.wait()` until kernel events arrive
    /// or the wakeup channel fires (from `enqueue()`). Domain-specific event
    /// dispatch lives in the tick body.
    ///
    /// ## Race Safety
    ///
    /// The tick body runs on the executor's own thread — the same thread that
    /// dispatches actor jobs. Domain state touched by tick is single-threaded.
    /// See research doc V5.
    ///
    /// ## Lifecycle
    /// Call `shutdown()` before deallocation.
    public final class Polling: SerialExecutor, TaskExecutor, @unchecked Sendable {

        private var jobs: Executor_Primitives.Executor.Job.Queue
        private var drainBuffer: Executor_Primitives.Executor.Job.Queue
        private let queueLock: Kernel.Thread.Mutex
        private var waitSource: Executor_Primitives.Executor.Wait.Event.Source
        private let _shutdown: Executor_Primitives.Executor.Shutdown.Flag
        private var threadHandle: Kernel.Thread.Handle?
        private let maxEventsPerPoll: Int
        private let tick: @Sendable (UnsafeBufferPointer<Kernel.Event>) -> Outcome

        /// Creates a polling executor.
        ///
        /// Spawns an OS thread that runs the event loop. The run loop blocks in
        /// the event source's poll until events arrive or the wakeup channel
        /// fires, then invokes `tick` with the received events.
        ///
        /// - Parameters:
        ///   - source: The kernel event source to poll. Consumed.
        ///   - maxEventsPerPoll: Maximum events per poll cycle. Default 256.
        ///   - tick: Called each iteration with the events from the current poll
        ///     cycle. Returns `.continue` to keep running or `.halt` to stop.
        ///     Runs on the executor's own thread. The buffer pointer is valid
        ///     only for the duration of the call.
        public init(
            source: consuming Kernel.Event.Source,
            maxEventsPerPoll: Int = 256,
            tick: @escaping @Sendable (UnsafeBufferPointer<Kernel.Event>) -> Outcome
        ) {
            self.jobs = .init()
            self.drainBuffer = .init()
            self.queueLock = .init()
            self.waitSource = .init(source: consume source)
            self._shutdown = .init()
            self.maxEventsPerPoll = maxEventsPerPoll
            unsafe (self.tick = tick)
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
    /// Direct access to the underlying event source for registration
    /// and configuration. Coroutine-scoped — the reference cannot escape.
    ///
    /// MUST be called from the executor's own thread (actor methods
    /// pinned to this executor). Single-threaded access is guaranteed
    /// by actor isolation, not by this accessor.
    public var source: Kernel.Event.Source {
        _read { yield waitSource.source }
        _modify { yield &waitSource.source }
    }
}

// MARK: - Shutdown

extension Kernel.Thread.Executor.Polling {
    /// Signal the run loop to halt and clean up the thread.
    ///
    /// Safe to call from any thread, including the executor's own thread.
    /// When called from the executor's own thread (e.g., actor deinit
    /// dispatched on this executor), the thread is detached instead of
    /// joined — the thread exits promptly because `_shutdown` is set
    /// and any `[weak self]` tick closure returns `.halt`.
    public func shutdown() {
        _shutdown.set()
        waitSource.wakeup.wake()
        if let handle = threadHandle.take() {
            if handle.isCurrent {
                handle.detach()
            } else {
                handle.join()
            }
        }
    }
}

// MARK: - Run Loop

extension Kernel.Thread.Executor.Polling {
    private func runLoop() {
        var eventBuffer = Array<Kernel.Event>(repeating: Kernel.Event.empty, count: maxEventsPerPoll)
        while !_shutdown.isSet {
            drainJobs()
            if _shutdown.isSet { break }
            do throws(Kernel.Event.Driver.Error) {
                let count = try waitSource.wait(deadline: nil, into: &eventBuffer)
                if _shutdown.isSet { break }
                let outcome = unsafe eventBuffer.withUnsafeBufferPointer { base in
                    let events = unsafe UnsafeBufferPointer<Kernel.Event>(
                        start: base.baseAddress, count: count
                    )
                    return unsafe tick(events)
                }
                if case .halt = outcome { _shutdown.set(); break }
            } catch {
                Kernel.Thread.yield()
            }
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
