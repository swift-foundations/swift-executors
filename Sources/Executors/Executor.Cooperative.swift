//
//  Executor.Cooperative.swift
//  swift-executors
//

extension Executor {
    /// Runs on the caller's thread; no OS thread spawned.
    ///
    /// Caller drives the run loop explicitly via `run()`. Closest analogs:
    /// Tokio `current_thread`, futures-rs `LocalPool`, Apple `CooperativeExecutor`.
    ///
    /// ## Usage
    /// ```swift
    /// let executor = Executor.Cooperative()
    /// // From another task:
    /// executor.enqueue(job)
    /// // On the calling thread:
    /// executor.run()   // blocks until shutdownNow() is called
    /// ```
    public final class Cooperative: SerialExecutor, @unchecked Sendable {
        private var jobs: Executor.Job.Queue
        private let wait: Executor.Wait.Condvar
        private let _shutdown: Executor.Shutdown.Flag

        public init() {
            self.jobs = .init()
            self.wait = .init()
            self._shutdown = .init()
        }
    }
}

// MARK: - SerialExecutor

extension Executor.Cooperative {
    public func enqueue(_ job: consuming ExecutorJob) {
        enqueue(UnownedJob(job))
    }

    public func enqueue(_ job: UnownedJob) {
        wait.withLock { jobs.enqueue(job) }
        wait.wake()
    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        unsafe UnownedSerialExecutor(ordinary: self)
    }
}

// MARK: - Run Loop

extension Executor.Cooperative {
    /// Drive the run loop on the caller's thread. Returns when `shutdownNow()` is called.
    public func run() {
        while !_shutdown.isSet {
            let job: UnownedJob? = wait.withLock {
                while jobs.isEmpty && !_shutdown.isSet { wait.wait() }
                return jobs.dequeue()
            }
            guard let job else { return }
            unsafe job.runSynchronously(on: asUnownedSerialExecutor())
        }
    }

    /// Signal the run loop to exit.
    public func shutdownNow() {
        _shutdown.set()
        wait.wakeAll()
    }
}
