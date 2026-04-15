//
//  Executor.Main Tests.swift
//  swift-executors
//

import Testing
import Executors

@Suite
struct MainTests {
    @Test("Main.shared returns an identity")
    func sharedIdentity() {
        let main = Executor.Main.shared
        _ = main.asUnownedSerialExecutor()
    }
}
