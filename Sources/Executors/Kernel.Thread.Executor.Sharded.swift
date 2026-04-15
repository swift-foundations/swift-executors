//
//  Kernel.Thread.Executor.Sharded.swift
//  swift-executors
//
//  Created by Coen ten Thije Boonkkamp on 28/12/2025.
//

import Synchronization
import Index_Primitives
import Ordinal_Primitives

extension Kernel.Thread.Executor {
    /// A sharded pool of serial executors for parallel work dispatch.
    ///
    /// Distributes work across N independent `Kernel.Thread.Executor` instances
    /// via round-robin selection. Each executor has its own OS thread and
    /// serial job queue.
    ///
    /// ## Thread Safety
    /// This type is `Sendable`. The round-robin counter uses atomic operations,
    /// making `next()` safe to call from any thread without synchronization.
    ///
    /// ## Lifecycle Requirements
    /// **IMPORTANT**: The pool owns its executor threads and must be explicitly shut down:
    ///
    /// 1. Call `shutdown()` before the pool is deallocated
    /// 2. Do NOT call `shutdown()` from any of the executor threads (deadlock)
    /// 3. After shutdown, the pool cannot be reused
    ///
    /// ## Usage
    /// ```swift
    /// let pool = Kernel.Thread.Executor.Sharded(.init(count: 4))
    /// defer { pool.shutdown() }
    ///
    /// let executor = pool.next()
    /// // Use executor for task dispatch or actor pinning
    /// ```
    public final class Sharded: Sendable {
        private let executors: [Kernel.Thread.Executor]
        public let count: Kernel.Thread.Count
        private let cursor: Atomic<Index<Kernel.Thread>>

        /// Creates a new sharded executor pool with the given options.
        ///
        /// Threads start immediately upon pool creation.
        public init(_ options: Options = .init()) {
            self.count = options.count
            self.executors = Array(count: options.count) { _ in Kernel.Thread.Executor() }
            self.cursor = .init(.zero)
        }
    }
}

extension Kernel.Thread.Executor.Sharded {
    /// Get the next executor using round-robin assignment.
    ///
    /// Each call atomically advances the cursor, distributing work evenly
    /// across available executor threads.
    ///
    /// ## Thread Safety
    /// Safe to call from any thread. The cursor is an atomic typed position;
    /// `advance(within:)` keeps it in `[0, count)` via CAS.
    ///
    /// - Returns: The next executor in the round-robin sequence.
    public func next() -> Kernel.Thread.Executor {
        executors[cursor.advance(within: count)]
    }

    /// Get a specific executor by index.
    ///
    /// Useful for explicit pinning when you want control over which
    /// executor a task uses.
    ///
    /// - Parameter index: The executor index (wraps around if >= count).
    public func executor(at index: Int) -> Kernel.Thread.Executor {
        executors[index % executors.count]
    }

    /// Shutdown all executor threads in the pool.
    ///
    /// Signals each executor's run loop to exit after processing remaining jobs,
    /// then joins all threads. This method blocks until all threads have terminated.
    ///
    /// ## Threading
    /// - **Blocking**: This method blocks the calling thread until all executor
    ///   threads have completed.
    /// - **Precondition**: Must NOT be called from any of the executor threads.
    ///   Doing so would deadlock (joining a thread from itself).
    ///
    /// ## Lifecycle
    /// - Must be called exactly once before the pool is deallocated
    /// - After shutdown, the pool cannot be reused
    /// - Jobs enqueued after shutdown begins are silently dropped
    public func shutdown() {
        for executor in executors {
            executor.shutdown()
        }
    }
}
