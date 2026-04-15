//
//  Executor.Scheduled.swift
//  swift-executors
//

extension Executor {
    /// Adds deadline-scheduled enqueue to any underlying serial executor.
    ///
    /// Owns an `Executor.Job.Priority` queue plus a timer thread that blocks
    /// on the priority queue's head deadline. When the head fires, the job is
    /// moved onto the `Base` executor via `Base.enqueue`. Delegation model.
    ///
    /// ## Lifecycle
    /// Call `shutdown()` before deallocation.
    public final class Scheduled<Base: SerialExecutor & Sendable>: SerialExecutor, @unchecked Sendable {
        private let base: Base
        private var priority: Executor.Job.Priority
        private let wait: Executor.Wait.Condvar
        private let _shutdown: Executor.Shutdown.Flag
        private var timerThread: Kernel.Thread.Handle?

        /// Creates a scheduled executor wrapping the given base.
        ///
        /// A timer thread starts immediately and waits on the priority queue.
        public init(base: Base) {
            self.base = base
            self.priority = .init()
            self.wait = .init()
            self._shutdown = .init()
            self.timerThread = unsafe Kernel.Thread.trap(Ownership.Transfer.Retained(self)) { retained in
                retained.take().runTimerLoop()
            }
        }
    }
}

// MARK: - SerialExecutor

extension Executor.Scheduled {
    /// Immediate enqueue delegates to the base executor.
    public func enqueue(_ job: consuming ExecutorJob) {
        base.enqueue(consume job)
    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        base.asUnownedSerialExecutor()
    }
}

// MARK: - TaskExecutor (conditional)

extension Executor.Scheduled: TaskExecutor where Base: TaskExecutor {
    public func asUnownedTaskExecutor() -> UnownedTaskExecutor {
        base.asUnownedTaskExecutor()
    }
}

// MARK: - Scheduled Enqueue

extension Executor.Scheduled {
    /// Enqueue a job for execution at a future deadline.
    ///
    /// The job is placed into the internal priority queue and the timer thread
    /// wakes to re-evaluate the head deadline.
    public func enqueue(
        _ job: consuming ExecutorJob,
        after delay: Duration
    ) {
        let deadline = ContinuousClock.now.advanced(by: delay)
        let unowned = UnownedJob(job)
        wait.withLock {
            priority.schedule(unowned, at: deadline)
        }
        wait.wake()
    }
}

// MARK: - Shutdown

extension Executor.Scheduled {
    /// Shutdown the timer thread. Does NOT shutdown the base executor.
    public func shutdown() {
        _shutdown.set()
        wait.wake.all()
        timerThread.take()?.join()
    }
}

// MARK: - Timer Loop

extension Executor.Scheduled {
    private func runTimerLoop() {
        var readyJobs: [UnownedJob] = []
        while !_shutdown.isSet {
            readyJobs.removeAll(keepingCapacity: true)
            wait.withLock {
                while !_shutdown.isSet {
                    guard let deadline = priority.peek else {
                        wait.wait()
                        continue
                    }
                    let now = ContinuousClock.now
                    if deadline <= now {
                        priority.drain(now: now) { readyJobs.append($0) }
                        break
                    } else {
                        let remaining = now.duration(to: deadline)
                        _ = wait.wait(timeout: remaining)
                    }
                }
            }
            // Enqueue outside the lock
            for job in readyJobs {
                base.enqueue(unsafe ExecutorJob(job))
            }
        }
    }
}
