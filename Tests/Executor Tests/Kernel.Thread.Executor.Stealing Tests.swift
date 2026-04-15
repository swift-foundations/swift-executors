//
//  Kernel.Thread.Executor.Stealing Tests.swift
//  swift-executors
//

import Testing
import Executors
import Kernel_Test_Support

extension Kernel.Thread.Executor.Stealing {
    enum Test {
        @Suite struct Unit {}
    }
}

extension Kernel.Thread.Executor.Stealing.Test.Unit {
    @Test("stealing pool creates and shuts down")
    func createsAndShuts() {
        let pool = Kernel.Thread.Executor.Stealing(.init(count: try! .init(2)))
        pool.shutdown()
    }
}
