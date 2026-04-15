//
//  Kernel.Thread.Executor.Stealing.swift
//  swift-executors
//

import Synchronization
import Index_Primitives
import Ordinal_Primitives

extension Kernel.Thread.Executor {
    /// N-owned-threads with per-thread deques and work-stealing.
    ///
    /// Each worker owns its `Executor.Job.Deque`. Workers steal from each other
    /// when their own deque is empty. Unlike `Sharded`, jobs are not pinned to a
    /// specific thread — any worker can run any job — so only `TaskExecutor`
    /// conformance is appropriate (stealing violates serial execution order).
    ///
    /// ## Lifecycle
    /// Call `shutdown()` before deallocation. Must not be called from a worker thread.
    public final class Stealing: TaskExecutor, @unchecked Sendable {
        internal let workers: [Worker]
        internal let _shutdown: Executor_Primitives.Executor.Shutdown.Flag
        private let cursor: Atomic<Index<Kernel.Thread>>
        public let count: Kernel.Thread.Count

        public init(_ options: Options = .init()) {
            self.count = options.count
            self._shutdown = .init()
            self.cursor = .init(.zero)
            self.workers = Array(count: options.count) { position in
                Worker(id: Int(bitPattern: position.ordinal))
            }
            for worker in workers {
                worker.start(pool: self)
            }
        }
    }
}

// MARK: - TaskExecutor

extension Kernel.Thread.Executor.Stealing {
    public func enqueue(_ job: consuming ExecutorJob) {
        enqueue(UnownedJob(job))
    }

    public func enqueue(_ job: UnownedJob) {
        workers[cursor.advance(within: count)].enqueue(job)
    }

    public func asUnownedTaskExecutor() -> UnownedTaskExecutor {
        unsafe UnownedTaskExecutor(ordinary: self)
    }
}

// MARK: - Shutdown

extension Kernel.Thread.Executor.Stealing {
    /// Shutdown all worker threads.
    ///
    /// Signals each worker's run loop to exit, wakes all, then joins all threads.
    public func shutdown() {
        _shutdown.set()
        for worker in workers { worker.wake() }
        for worker in workers { worker.join() }
    }
}
