//
//  Executor.Wait.Condvar.Wake.swift
//  swift-executors
//

public import Property_Primitives
internal import Synchronizer_Blocking

extension Executor.Wait.Condvar {
    /// Tag for wake operations.
    public enum Wake {}
}

// MARK: - Accessor

extension Executor.Wait.Condvar {
    /// Access to wake operations.
    ///
    /// - `wake()` — signal a single waiter.
    /// - `wake.all()` — broadcast to all waiters (shutdown).
    public var wake: Property<Wake, Executor.Wait.Condvar> {
        Property(self)
    }
}

// MARK: - Property Extensions

extension Property where Tag == Executor.Wait.Condvar.Wake, Base == Executor.Wait.Condvar {
    /// Wake a single waiter. Thread-safe; does not require holding the lock.
    public func callAsFunction() {
        base.sync.signal()
    }

    /// Wake every waiter. Used on shutdown to force all workers to re-check
    /// the shutdown flag.
    public func all() {
        base.sync.broadcast()
    }
}
