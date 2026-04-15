//
//  Kernel.Thread.Executor.Stealing.Options.swift
//  swift-executors
//

extension Kernel.Thread.Executor.Stealing {
    /// Configuration options for the work-stealing executor pool.
    public struct Options: Sendable {
        /// Number of worker threads.
        public var count: Kernel.Thread.Count

        public init(count: Kernel.Thread.Count? = nil) {
            self.count = count
                ?? Kernel.Thread.Count.min(
                    Self.defaultCount,
                    Kernel.System.Processor.count.retag(Kernel.Thread.self)
                )
        }
    }
}

extension Kernel.Thread.Executor.Stealing.Options {
    private static let defaultCount: Kernel.Thread.Count = try! .init(4)
}
