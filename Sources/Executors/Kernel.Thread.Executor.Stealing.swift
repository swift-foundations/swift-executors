//
//  Kernel.Thread.Executor.Stealing.swift
//  swift-executors
//

import Synchronization

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
        private let workers: [Worker]
        private let _shutdown: Executor_Primitives.Executor.Shutdown.Flag
        private let nextVictim: Atomic<UInt64>
        public let count: Kernel.Thread.Count

        public init(_ options: Options = .init()) {
            self.count = options.count
            self._shutdown = .init()
            self.nextVictim = .init(0)
            let workerCount = Int(options.count)
            self.workers = (0..<workerCount).map { id in Worker(id: id) }
            for worker in workers {
                worker.start(pool: self)
            }
        }
    }
}

// MARK: - Options

extension Kernel.Thread.Executor.Stealing {
    /// Configuration options for the work-stealing executor pool.
    public struct Options: Sendable {
        /// Number of worker threads.
        public var count: Kernel.Thread.Count

        private static let defaultCount: Kernel.Thread.Count = try! .init(4)

        public init(count: Kernel.Thread.Count? = nil) {
            self.count = count
                ?? Kernel.Thread.Count.min(
                    Self.defaultCount,
                    Kernel.System.Processor.count.retag(Kernel.Thread.self)
                )
        }
    }
}

// MARK: - TaskExecutor

extension Kernel.Thread.Executor.Stealing {
    public func enqueue(_ job: consuming ExecutorJob) {
        enqueue(UnownedJob(job))
    }

    public func enqueue(_ job: UnownedJob) {
        let victim = Int(nextVictim.wrappingAdd(1, ordering: .relaxed).oldValue) % workers.count
        workers[victim].enqueue(job)
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

// MARK: - Worker

extension Kernel.Thread.Executor.Stealing {
    final class Worker: @unchecked Sendable {
        let id: Int
        private var deque: Executor_Primitives.Executor.Job.Deque
        private let wait: Executor.Wait.Condvar
        private var handle: Kernel.Thread.Handle?

        init(id: Int) {
            self.id = id
            self.deque = .init()
            self.wait = .init()
        }

        func start(pool: Kernel.Thread.Executor.Stealing) {
            self.handle = unsafe Kernel.Thread.trap(Ownership.Transfer.Retained(self)) { retained in
                let worker = retained.take()
                worker.runLoop(pool: pool)
            }
        }

        func enqueue(_ job: UnownedJob) {
            wait.withLock { deque.push(job) }
            wait.wake()
        }

        func wake() { wait.wakeAll() }

        func join() { handle.take()?.join() }

        private func runLoop(pool: Kernel.Thread.Executor.Stealing) {
            while !pool._shutdown.isSet {
                // Own deque — under own lock
                if let job = wait.withLock({ deque.pop() }) {
                    unsafe job.runSynchronously(on: pool.asUnownedTaskExecutor())
                    continue
                }
                // Steal — NOT under own lock, only victim's
                var stolen: UnownedJob? = nil
                for offset in 1..<pool.workers.count {
                    let victim = (id + offset) % pool.workers.count
                    if let job = pool.workers[victim].trySteal() {
                        stolen = job
                        break
                    }
                }
                if let job = stolen {
                    unsafe job.runSynchronously(on: pool.asUnownedTaskExecutor())
                    continue
                }
                // Wait — under own lock
                wait.withLock {
                    if !pool._shutdown.isSet && deque.isEmpty {
                        wait.wait()
                    }
                }
            }
            // Drain remaining
            while let job = wait.withLock({ deque.pop() }) {
                unsafe job.runSynchronously(on: pool.asUnownedTaskExecutor())
            }
        }

        fileprivate func trySteal() -> UnownedJob? {
            wait.withLock { deque.steal() }
        }
    }
}
