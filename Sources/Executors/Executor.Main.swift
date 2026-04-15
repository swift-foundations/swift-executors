//
//  Executor.Main.swift
//  swift-executors
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import Dispatch
#endif

extension Executor {
    /// Main-thread serial executor.
    ///
    /// On Darwin, delegates to `DispatchQueue.main` for automatic main-thread
    /// integration. On Linux/Windows, provides a condvar-based pump that the
    /// consumer must drive via `run()`.
    ///
    /// ## Safety Invariant
    ///
    /// This type is `Sendable` by virtue of internal synchronization:
    /// - On Darwin, all enqueue paths dispatch into `DispatchQueue.main`,
    ///   which owns its own lock-free MPSC enqueue primitive and is
    ///   architecturally Sendable.
    /// - On Linux / Windows, the job queue (`jobs`), condition variable
    ///   (`wait`), and shutdown flag (`_shutdown`) are mutated exclusively
    ///   under `wait: Executor.Wait.Condvar` -- a mutex + condvar wrapper.
    ///   `enqueue`, `run`, and `shutdown` route state accesses through
    ///   `wait.withLock`.
    ///
    /// The caller MUST interact with the executor only through its public
    /// API. Do not read or mutate the platform-specific stored state
    /// directly.
    ///
    /// ## Intended Use
    ///
    /// - Pinning actors to the OS main thread via `Executor.Main.shared`.
    /// - Providing a SerialExecutor target on platforms without an ambient
    ///   main run loop (Linux, Windows) by manually driving `run()` from
    ///   the main thread.
    ///
    /// ## Non-Goals
    ///
    /// - Not a TaskExecutor. Main-thread dispatch implies serial ordering;
    ///   task-executor semantics are not offered.
    /// - Not a substitute for `DispatchMain()`. On Linux/Windows the pump
    ///   blocks only until `shutdown()`; there is no ambient integration
    ///   with OS run loops.
    /// - Not multi-instance. The type is exposed only via
    ///   `Executor.Main.shared`.
    public final class Main: SerialExecutor, @unsafe @unchecked Sendable {
        #if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
        private var jobs: Executor.Job.Queue
        private let wait: Executor.Wait.Condvar
        private let _shutdown: Executor.Shutdown.Flag
        #endif

        private init() {
            #if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
            self.jobs = .init()
            self.wait = .init()
            self._shutdown = .init()
            #endif
        }
    }
}

// MARK: - Shared

extension Executor.Main {
    /// The shared main executor instance.
    public static let shared: Executor.Main = .init()
}

// MARK: - SerialExecutor

extension Executor.Main {
    public func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        DispatchQueue.main.async {
            unsafe unowned.runSynchronously(
                on: self.asUnownedSerialExecutor()
            )
        }
        #else
        wait.withLock { jobs.enqueue(unowned) }
        wait.wake()
        #endif
    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        unsafe UnownedSerialExecutor(ordinary: self)
    }
}

// MARK: - Main Loop (Linux/Windows)

#if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
extension Executor.Main {
    /// Drive the main pump on the calling thread. Blocks until `shutdown()`.
    ///
    /// - Important: Must be called from the main thread.
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

    /// Signal the main pump to exit.
    public func shutdown() {
        _shutdown.set()
        wait.wake.all()
    }
}
#endif
