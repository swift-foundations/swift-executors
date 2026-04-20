//
//  Executor.Scheduled Tests.swift
//  swift-executors
//

import Testing
import Executors

@Suite
struct ScheduledTests {
    @Test
    func `scheduled wraps base executor`() {
        let base = Kernel.Thread.Executor()
        let scheduled = Executor.Scheduled(base: base)
        defer {
            scheduled.shutdown()
            base.shutdown()
        }
        _ = scheduled.asUnownedSerialExecutor()
    }
}
