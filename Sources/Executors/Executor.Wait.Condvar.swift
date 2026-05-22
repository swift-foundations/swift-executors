//
//  Executor.Wait.Condvar.swift
//  swift-executors
//

internal import Synchronizer_Blocking

extension Executor.Wait {
    /// Wait primitive backed by pthread_cond_wait.
    ///
    /// The lock IS the queue-protecting lock. `wait` releases it atomically;
    /// `wake()` signals one waiter; `wake.all()` broadcasts.
    ///
    /// ## Wait.Primitive contract
    ///
    /// This type and `Executor.Wait.Event.Source` (in swift-executor-primitives)
    /// satisfy the conceptual Wait.Primitive contract statically. When a third
    /// wait mechanism ships, `Wait.Primitive` becomes a real protocol — each
    /// existing type gains a retroactive conformance via typealias bridge
    /// (non-breaking).
    public final class Condvar: Sendable {
        internal let sync: Synchronizer.Blocking<1>

        public init() {
            self.sync = .init()
        }
    }
}

extension Executor.Wait.Condvar {
    /// Execute a closure while holding the lock.
    public func withLock<R, E: Swift.Error>(
        _ body: () throws(E) -> R
    ) throws(E) -> R {
        try sync.synchronize(body)
    }

    /// Wait until signaled. Caller must already hold the lock (via `withLock`);
    /// wait releases it atomically and re-acquires on return.
    public func wait() {
        sync.wait()
    }

    /// Wait with timeout. Returns `true` if signaled, `false` if timed out.
    public func wait(timeout: Duration) -> Bool {
        sync.wait(timeout: timeout)
    }
}
