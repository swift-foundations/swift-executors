//
//  Executor.Scheduled Tests.swift
//  swift-executors
//

import Testing
import Executors

@Suite
struct ScheduledTests {
    @Test("scheduled wraps base executor")
    func wrapsBase() {
        let base = Kernel.Thread.Executor()
        let scheduled = Executor.Scheduled(base: base)
        defer {
            scheduled.shutdown()
            base.shutdown()
        }
        _ = scheduled.asUnownedSerialExecutor()
    }
}
