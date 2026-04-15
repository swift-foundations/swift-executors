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
    /// consumer must drive via `runMainLoop()`.
    ///
    /// ## Platform asymmetry
    ///
    /// - **Darwin**: Jobs dispatched to `DispatchQueue.main`. No manual pumping
    ///   needed — the platform's main run loop drives execution automatically.
    /// - **Linux/Windows**: No OS-level main run loop exists. Consumer must call
    ///   `runMainLoop()` from the main thread. Semantically equivalent but not
    ///   automatic. `runMainLoop()` blocks until `shutdownNow()` is called.
    public final class Main: SerialExecutor, @unchecked Sendable {
        #if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
        private var jobs: Executor.Job.Queue
        private let wait: Executor.Wait.Condvar
        private let _shutdown: Executor.Shutdown.Flag
        #endif

        /// The shared main executor instance.
        public static let shared: Main = .init()

        private init() {
            #if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
            self.jobs = .init()
            self.wait = .init()
            self._shutdown = .init()
            #endif
        }
    }
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
    /// Drive the main pump on the calling thread. Blocks until `shutdownNow()`.
    ///
    /// - Important: Must be called from the main thread.
    public func runMainLoop() {
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
    public func shutdownNow() {
        _shutdown.set()
        wait.wakeAll()
    }
}
#endif
