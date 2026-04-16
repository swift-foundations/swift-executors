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
        /// Per-worker XorShift32 state for random victim selection.
        /// Mutated only from this worker's own runLoop (single-writer),
        /// so no synchronization needed.
        private var rngState: UInt32

        init(id: Int) {
            self.id = id
            self.deque = .init(capacity: 1024)
            self.wait = .init()
            // XorShift32 requires non-zero state; OR with 1 guarantees it.
            self.rngState = UInt32(truncatingIfNeeded: id) &+ 0x9E3779B9
            if self.rngState == 0 { self.rngState = 1 }
        }

        /// Advance the XorShift32 PRNG and return the next 32-bit value.
        ///
        /// From Marsaglia 2003: period = 2^32 − 1, non-zero state.
        /// One multiplication-free mix per call; dominated by the three
        /// shifts on modern hardware.
        private func nextRandom() -> UInt32 {
            rngState ^= rngState &<< 13
            rngState ^= rngState &>> 17
            rngState ^= rngState &<< 5
            return rngState
        }

        func start(pool: Kernel.Thread.Executor.Stealing) {
            self.handle = unsafe Kernel.Thread.trap(Ownership.Transfer.Retained(self)) { retained in
                let worker = retained.take()
                worker.runLoop(pool: pool)
            }
        }

        func enqueue(_ job: UnownedJob) {
            wait.withLock { _ = deque.push(job) }
            wait.wake()
        }

        func wake() { wait.wake.all() }

        func join() { handle.take()?.join() }

        private func runLoop(pool: Kernel.Thread.Executor.Stealing) {
            while !pool._shutdown.isSet {
                // Own deque — under own lock
                if let job = wait.withLock({ deque.take() }) {
                    unsafe Kernel.Thread.Executor.runJob(
                        job,
                        onTask: pool.asUnownedTaskExecutor(),
                        priorityTracking: pool.priorityTracking
                    )
                    continue
                }
                // Steal — NOT under own lock, only victim's.
                // Random victim selection via per-worker XorShift32 PRNG
                // per work-stealing-scheduler-design.md Q2. Up to N-1
                // attempts; each attempt uniformly samples a non-self
                // peer.
                var stolen: UnownedJob? = nil
                let n = pool.workers.count
                if n > 1 {
                    for _ in 0..<(n - 1) {
                        var victim = Int(nextRandom() % UInt32(n))
                        if victim == id {
                            victim = (victim + 1) % n
                        }
                        if let job = pool.workers[victim].trySteal() {
                            stolen = job
                            break
                        }
                    }
                }
                if let job = stolen {
                    unsafe Kernel.Thread.Executor.runJob(
                        job,
                        onTask: pool.asUnownedTaskExecutor(),
                        priorityTracking: pool.priorityTracking
                    )
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
            while let job = wait.withLock({ deque.take() }) {
                unsafe Kernel.Thread.Executor.runJob(
                    job,
                    onTask: pool.asUnownedTaskExecutor(),
                    priorityTracking: pool.priorityTracking
                )
            }
        }

        fileprivate func trySteal() -> UnownedJob? {
            wait.withLock { deque.steal() }
        }
    }
}
