//
//  Kernel.Thread.Executor.Stealing.Worker.swift
//  swift-executors
//

extension Kernel.Thread.Executor.Stealing {
    package final class Worker: @unchecked Sendable {
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
