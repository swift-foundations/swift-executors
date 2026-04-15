//
//  Executor.Cooperative Tests.swift
//  swift-executors
//

import Testing
import Executors

@Suite
struct CooperativeTests {
    @Test("cooperative executor can be created and shut down")
    func createAndShutdown() {
        let executor = Executor.Cooperative()
        executor.shutdown()
    }
}
