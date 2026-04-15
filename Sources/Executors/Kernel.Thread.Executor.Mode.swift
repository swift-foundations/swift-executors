//
//  Kernel.Thread.Executor.Mode.swift
//  swift-executors
//

extension Kernel.Thread.Executor {
    /// Controls which executor identity is reported to the runtime when
    /// running jobs.
    public enum Mode {
        /// Report as serial executor. Use for actor pinning.
        case serial
        /// Report as task executor. Use with `withTaskExecutorPreference`.
        case task
    }
}
