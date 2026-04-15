//
//  Kernel.Thread.Executor.swift
//  swift-executors
//
//  Created by Coen ten Thije Boonkkamp on 28/12/2025.
//

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
        private let wait: Executor_Primitives.Executor.Wait.Condvar
        private var jobs: Executor_Primitives.Executor.Job.Queue
        private let _shutdown: Executor_Primitives.Executor.Shutdown.Flag
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
            self.wait = .init()
            self.jobs = .init()
            self._shutdown = .init()

            self.threadHandle = unsafe Kernel.Thread.trap(Ownership.Transfer.Retained(self)) { retained in
                let executor = retained.take()
                executor.runLoop()
            }
        }

        deinit {
            guard let handle = threadHandle.take() else { return }
            wait.withLock {
                _shutdown.set()
            }
            wait.wakeAll()
            handle.detach()
        }
    }
}

// MARK: - SerialExecutor

extension Kernel.Thread.Executor {
    public func enqueue(_ job: UnownedJob) {
        let runInline: Bool = wait.withLock {
            guard !_shutdown.isSet else { return true }
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
            wait.wake()
        }
    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        unsafe UnownedSerialExecutor(ordinary: self)
    }
}

// MARK: - TaskExecutor

extension Kernel.Thread.Executor {
    public func enqueue(_ job: consuming ExecutorJob) {
        enqueue(UnownedJob(job))
    }
}

// MARK: - Run Loop

extension Kernel.Thread.Executor {
    fileprivate func runLoop() {
        while true {
            let job: UnownedJob? = wait.withLock {
                while jobs.isEmpty && !_shutdown.isSet {
                    wait.wait()
                }
                guard !_shutdown.isSet || !jobs.isEmpty else { return nil }
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
    /// then joins the thread.
    ///
    /// - Precondition: Must NOT be called from the executor thread itself.
    /// - Precondition: Must be called exactly once before the executor is deallocated.
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

        wait.withLock {
            _shutdown.set()
        }
        wait.wakeAll()
        handle.join()
    }
}
