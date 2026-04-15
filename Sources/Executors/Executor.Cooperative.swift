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
    /// ## Safety Invariant
    ///
    /// This type is `Sendable` by virtue of internal synchronization: the
    /// job queue (`jobs`), condition variable (`wait`), and shutdown flag
    /// (`_shutdown`) are mutated exclusively under `wait: Executor.Wait.Condvar`
    /// -- a mutex + condvar wrapper. `enqueue`, `run`, and `shutdown` route
    /// state accesses through `wait.withLock`. The caller MUST interact with
    /// the executor only through its public API; touching the stored state
    /// directly is undefined behaviour.
    ///
    /// ## Intended Use
    ///
    /// - Single-threaded cooperative task execution on the caller's thread
    ///   (e.g., test harnesses, deterministic simulation, REPL drivers).
    /// - Unit tests that need a drain-to-completion executor without
    ///   spawning an OS thread.
    ///
    /// ## Non-Goals
    ///
    /// - Not a TaskExecutor. Cooperative scheduling implies serial actor
    ///   identity; task-executor semantics are not offered.
    /// - Not multi-thread. Enqueues from other threads are allowed, but
    ///   execution is always on the `run()` caller.
    /// - Not reentrant within `run()`. Shutdown must be driven from another
    ///   context (or via a job that calls `shutdown()`).
    ///
    /// ## Usage
    /// ```swift
    /// let executor = Executor.Cooperative()
    /// // From another task:
    /// executor.enqueue(job)
    /// // On the calling thread:
    /// executor.run()   // blocks until shutdown() is called
    /// ```
    public final class Cooperative: SerialExecutor, @unsafe @unchecked Sendable {
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
    /// Drive the run loop on the caller's thread. Returns when `shutdown()` is called.
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
    public func shutdown() {
        _shutdown.set()
        wait.wake.all()
    }
}
