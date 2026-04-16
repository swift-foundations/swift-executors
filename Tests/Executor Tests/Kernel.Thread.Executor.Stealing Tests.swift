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

    @Test("priorityTracking defaults to false")
    func priorityTrackingDefaultsFalse() {
        let options = Kernel.Thread.Executor.Stealing.Options(count: try! .init(2))
        #expect(options.priorityTracking == false)
    }

    @Test("priorityTracking true runs jobs correctly")
    func priorityTrackingTrueRunsJobs() async {
        let pool = Kernel.Thread.Executor.Stealing(
            .init(count: try! .init(2), priorityTracking: true)
        )
        let result = await Task(executorPreference: pool) { 42 }.value
        #expect(result == 42)
        pool.shutdown()
    }
}
