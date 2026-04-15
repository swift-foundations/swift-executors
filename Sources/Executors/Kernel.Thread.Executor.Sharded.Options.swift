//
//  Kernel.Thread.Executor.Sharded.Options.swift
//  swift-executors
//
//  Created by Coen ten Thije Boonkkamp on 28/12/2025.
//

extension Kernel.Thread.Executor.Sharded {
    /// Configuration options for the sharded executor pool.
    public struct Options: Sendable {
        /// Number of executor threads in the pool.
        public var count: Kernel.Thread.Count

        /// Creates options with the specified thread count.
        ///
        /// - Parameter count: Number of threads. If nil, defaults to min(4, processorCount).
        public init(count: Kernel.Thread.Count? = nil) {
            self.count =
                count
                ?? Kernel.Thread.Count.min(
                    Self.defaultCount,
                    Kernel.System.Processor.count.retag(Kernel.Thread.self)
                )
        }
    }
}

extension Kernel.Thread.Executor.Sharded.Options {
    private static let defaultCount: Kernel.Thread.Count = try! .init(4)
}
