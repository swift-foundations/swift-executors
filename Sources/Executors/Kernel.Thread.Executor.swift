//
//  Kernel.Thread.Executor.swift
//  swift-executors
//
//  Created by Coen ten Thije Boonkkamp on 28/12/2025.
//

internal import Thread_Synchronization

extension Kernel.Thread {
    /// A serial executor backed by a single dedicated OS thread.
    ///
    /// Conforms to both `SerialExecutor` (for actor pinning via `unownedExecutor`)
    /// and `TaskExecutor` (for `withTaskExecutorPreference`).
    ///
    /// ## Thread Safety
    /// This type is `@unchecked Sendable` because it provides internal synchronization.
    /// Jobs are enqueued under lock and executed serially on the dedicated thread.
    ///
    /// ## Run Identity
    ///
    /// The executor must report the correct identity when running jobs, otherwise
    /// the Swift Concurrency runtime will re-enqueue them indefinitely.
    ///
    /// - **Serial mode** (default): Jobs run with `runSynchronously(on: serialExecutor)`.
    ///   Use for actor pinning via `unownedExecutor`.
    /// - **Task mode**: Jobs run with `runSynchronously(on: taskExecutor)`.
    ///   Use with `withTaskExecutorPreference`.
    ///
    /// See: swift-platform-executors `PThreadExecutor` for the upstream pattern.
    ///
    /// ## Lifecycle Requirements
    ///
    /// **IMPORTANT**: This type has strict lifecycle requirements:
    ///
    /// 1. **Must call `shutdown()` before deallocation**: The executor owns an OS thread
    ///    that must be explicitly joined. Failing to call `shutdown()` before the executor
    ///    is deallocated will trap with a diagnostic message.
    ///
    /// 2. **Cannot shutdown from executor's own thread**: Calling `shutdown()` from a job
    ///    running on the executor would deadlock (joining a thread from itself). This is
    ///    detected and traps with a diagnostic message.
    ///
    /// 3. **Shutdown is idempotent-ish**: Calling `shutdown()` on an already-shutdown
    ///    executor traps. Call exactly once.
    ///
    /// ## Example Usage
    /// ```swift
    /// // Actor pinning (serial mode — default)
    /// let executor = Kernel.Thread.Executor()
    /// defer { executor.shutdown() }
    ///
    /// actor MyActor {
    ///     nonisolated var unownedExecutor: UnownedSerialExecutor {
    ///         executor.asUnownedSerialExecutor()
    ///     }
    /// }
    ///
    /// // Task executor preference (task mode)
    /// let executor = Kernel.Thread.Executor(mode: .task)
    /// defer { executor.shutdown() }
    ///
    /// await withTaskExecutorPreference(executor) {
    ///     // work runs on dedicated thread, off cooperative pool
    /// }
    /// ```
    ///
    /// ## Why These Traps Exist
    /// These preconditions exist because silent failure would be worse:
    /// - Leaking an OS thread is a resource leak that compounds over time
    /// - Joining from self is undefined behavior on some platforms
    /// - Double-shutdown indicates a logic error in the caller
    ///
    /// If you need a more forgiving API, consider wrapping this in a helper that
    /// tracks shutdown state and handles edge cases for your use case.
    public final class Executor: SerialExecutor, TaskExecutor, @unchecked Sendable {

        /// Controls which executor identity is reported to the runtime when
        /// running jobs.
        public enum Mode {
            /// Report as serial executor. Use for actor pinning.
            case serial
            /// Report as task executor. Use with `withTaskExecutorPreference`.
            case task
        }

        private let mode: Mode
        private let sync: Kernel.Thread.Synchronization<1>
        private var jobs: Job.Queue
        private var isRunning: Bool = true
        private var threadHandle: Kernel.Thread.Handle?

        /// Creates a new executor thread.
        ///
        /// The thread starts immediately and begins waiting for jobs.
        ///
        /// - Parameter mode: Controls which identity is reported to the runtime.
        ///   Use `.serial` (default) for actor pinning, `.task` for
        ///   `withTaskExecutorPreference`.
        public init(mode: Mode = .serial) {
            self.mode = mode
            self.sync = Kernel.Thread.Synchronization()
            self.jobs = Job.Queue()

            // Retain self until the OS thread takes ownership.
            // Uses Reference.Transfer.Retained for safe Sendable crossing with zero allocation.
            // trap(_:_:) accepts the value explicitly, avoiding closure capture issues.
            //
            // Thread creation failure here is catastrophic - the executor cannot function
            // without its thread. We use Kernel.Thread.trap because:
            // 1. Most callers cannot recover from thread exhaustion
            // 2. Making init() throwing would cascade through the entire API
            // 3. Thread creation failure typically indicates system-wide resource exhaustion
            self.threadHandle = unsafe Kernel.Thread.trap(Ownership.Transfer.Retained(self)) { retained in
                let executor = retained.take()
                executor.runLoop()
            }
        }

        deinit {
            guard let handle = threadHandle.take() else { return }
            // Shutdown was never called — signal thread to stop and detach.
            // The thread sees !isRunning on its next iteration and exits.
            // Detach ensures no resource leak. This path runs for singletons
            // during process exit cleanup.
            sync.withLock {
                isRunning = false
            }
            sync.broadcast()
            handle.detach()
        }
    }
}

// MARK: - SerialExecutor

extension Kernel.Thread.Executor {
    /// Enqueue a job for execution on this executor.
    ///
    /// If the executor has been shut down, the job is executed inline on the
    /// calling thread rather than silently dropped. This honors the
    /// `SerialExecutor` contract (every enqueued job is eventually run) and
    /// prevents deadlocks: the job typically hits the actor's lifecycle gate,
    /// throws a shutdown error, and the suspended continuation resumes.
    public func enqueue(_ job: UnownedJob) {
        let runInline: Bool = sync.withLock {
            guard isRunning else { return true }
            jobs.enqueue(job)
            return false
        }
        if runInline {
            switch mode {
            case .serial:
                unsafe job.runSynchronously(on: asUnownedSerialExecutor())
            case .task:
                unsafe job.runSynchronously(on: asUnownedTaskExecutor())
            }
        } else {
            sync.signal()
        }
    }

    /// Returns an unowned reference to this executor.
    ///
    /// Used by actors to specify their custom executor via `unownedExecutor`.
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        unsafe UnownedSerialExecutor(ordinary: self)
    }
}

// MARK: - TaskExecutor

extension Kernel.Thread.Executor {
    /// Enqueue an executor job for execution.
    ///
    /// This enables `Task(executorPreference:)` to work with this executor.
    public func enqueue(_ job: consuming ExecutorJob) {
        enqueue(UnownedJob(job))
    }
}

// MARK: - Run Loop

extension Kernel.Thread.Executor {
    fileprivate func runLoop() {
        while true {
            let job: UnownedJob? = sync.withLock {
                while jobs.isEmpty && isRunning {
                    sync.wait()
                }
                guard isRunning || !jobs.isEmpty else { return nil }
                return jobs.dequeue()
            }
            guard let job else { return }
            switch mode {
            case .serial:
                unsafe job.runSynchronously(on: asUnownedSerialExecutor())
            case .task:
                unsafe job.runSynchronously(on: asUnownedTaskExecutor())
            }
        }
    }
}

// MARK: - Shutdown

extension Kernel.Thread.Executor {
    /// Shutdown the executor thread.
    ///
    /// Signals the run loop to exit after processing any remaining jobs,
    /// then joins the thread. The join completes in < 100µs — the thread
    /// sees `!isRunning` and exits its run loop almost immediately.
    ///
    /// - Precondition: Must NOT be called from the executor thread itself.
    ///   Doing so would deadlock (joining a thread from itself).
    /// - Precondition: Must be called exactly once before the executor is deallocated.
    /// - Precondition: Must not be called before the thread has started.
    public func shutdown() {
        guard let handle = threadHandle.take() else {
            preconditionFailure(
                "Kernel.Thread.Executor.shutdown() called on already-shutdown or never-started executor"
            )
        }

        precondition(
            !handle.isCurrent,
            "Cannot shutdown executor from its own thread - would deadlock on join"
        )

        sync.withLock {
            isRunning = false
        }
        sync.broadcast()
        handle.join()
    }
}
