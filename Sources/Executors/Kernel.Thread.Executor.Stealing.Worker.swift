//
//  Kernel.Thread.Executor.Stealing.Worker.swift
//  swift-executors
//

extension Kernel.Thread.Executor.Stealing {
    /// A single work-stealing worker owning one OS thread and one deque.
    ///
    /// ## Safety Invariant
    ///
    /// This type is `Sendable` by virtue of internal synchronization: the deque
    /// (`deque`) and the thread handle (`handle`) are mutated exclusively
    /// under `wait: Executor.Wait.Condvar`. The enqueue / pop / steal / wake
    /// / join paths all serialize through `wait.withLock`. Cross-worker steal
    /// attempts touch the victim's deque under the victim's own `wait` lock --
    /// never under the stealer's. The caller (the parent `Stealing` pool)
    /// MUST route all operations through the package-visible API.
    ///
    /// ## Intended Use
    ///
    /// - Internal building block of `Kernel.Thread.Executor.Stealing` --
    ///   one Worker per OS thread in the pool.
    /// - Hosts the work-stealing run loop: drain own deque, then attempt to
    ///   steal from peer workers, then block on condvar.
    ///
    /// ## Non-Goals
    ///
    /// - Not a public API. Consumers use `Kernel.Thread.Executor.Stealing`,
    ///   not `Worker` directly.
    /// - Not safe to use outside a `Stealing` pool -- lifetime and shutdown
    ///   semantics are owned by the pool.
    package final class Worker: @unsafe @unchecked Sendable {
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

        func wake() { wait.wake.all() }

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
