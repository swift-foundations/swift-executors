//
//  Kernel.Thread.Executor.Sharded Tests.swift
//  swift-executors
//

import Testing

@testable import Executors
import Kernel_Test_Support

extension Kernel.Thread.Executor.Sharded {
    enum Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests

extension Kernel.Thread.Executor.Sharded.Test.Unit {
    @Test("init with default options creates threads")
    func initDefaultOptions() {
        let pool = Kernel.Thread.Executor.Sharded()
        #expect(pool.count > 0)  // swiftlint:disable:this empty_count
        #expect(pool.count <= 4)  // Default is min(4, processorCount)
        pool.shutdown()
    }

    @Test("init with custom count")
    func initCustomCount() {
        let pool = Kernel.Thread.Executor.Sharded(.init(count: 2))
        #expect(pool.count == 2)
        pool.shutdown()
    }

    @Test("next returns an executor")
    func nextReturnsExecutor() {
        let pool = Kernel.Thread.Executor.Sharded(.init(count: 2))
        let executor = pool.next()
        _ = executor.asUnownedSerialExecutor()
        pool.shutdown()
    }

    @Test("executor(at:) returns executor at index")
    func executorAtIndex() {
        let pool = Kernel.Thread.Executor.Sharded(.init(count: 2))
        let e0 = pool.executor(at: 0)
        let e1 = pool.executor(at: 1)
        _ = e0.asUnownedSerialExecutor()
        _ = e1.asUnownedSerialExecutor()
        pool.shutdown()
    }

    @Test("executor(at:) wraps around")
    func executorAtIndexWraps() {
        let pool = Kernel.Thread.Executor.Sharded(.init(count: 2))
        let e0 = pool.executor(at: 0)
        let e2 = pool.executor(at: 2)  // Should wrap to index 0
        // Both return valid executors (may or may not be same instance)
        _ = e0.asUnownedSerialExecutor()
        _ = e2.asUnownedSerialExecutor()
        pool.shutdown()
    }

    @Test("shutdown completes gracefully")
    func shutdownCompletes() {
        let pool = Kernel.Thread.Executor.Sharded(.init(count: 2))
        pool.shutdown()
        // No hang = success
    }
}


// MARK: - Isolation Verification

extension Kernel.Thread.Executor.Sharded.Test.Unit {
    @Test("isIsolatingCurrentContext returns false from non-shard thread")
    func isolationFromNonShardThread() {
        let pool = Kernel.Thread.Executor.Sharded(.init(count: 2))
        #expect(pool.isIsolatingCurrentContext() == false)
        pool.shutdown()
    }

    @Test("isIsolatingCurrentContext returns true from shard thread")
    func isolationFromShardThread() async {
        let pool = Kernel.Thread.Executor.Sharded(.init(count: 2))
        let shard = pool.next()

        let result = await Task(executorPreference: shard) {
            pool.isIsolatingCurrentContext()
        }.value

        #expect(result == true)
        pool.shutdown()
    }

    @Test("isIsolatingCurrentContext returns false after shutdown")
    func isolationAfterShutdown() {
        let pool = Kernel.Thread.Executor.Sharded(.init(count: 2))
        pool.shutdown()
        #expect(pool.isIsolatingCurrentContext() == false)
    }
}

// MARK: - Integration Tests

extension Kernel.Thread.Executor.Sharded.Test.Integration {
    @Test("round-robin distributes across executors")
    func roundRobinDistribution() {
        let pool = Kernel.Thread.Executor.Sharded(.init(count: 2))

        // Get several executors via next()
        let e1 = pool.next()
        let e2 = pool.next()
        let e3 = pool.next()
        let e4 = pool.next()

        // Should cycle: e1 != e2, e1 == e3, e2 == e4
        let ref1 = ObjectIdentifier(e1)
        let ref2 = ObjectIdentifier(e2)
        let ref3 = ObjectIdentifier(e3)
        let ref4 = ObjectIdentifier(e4)

        #expect(ref1 != ref2)
        #expect(ref1 == ref3)
        #expect(ref2 == ref4)

        pool.shutdown()
    }

    @Test("tasks on different executors run independently")
    func tasksRunIndependently() async {
        let pool = Kernel.Thread.Executor.Sharded(.init(count: 2))

        let e1 = pool.executor(at: 0)
        let e2 = pool.executor(at: 1)

        // Use Sendable return values instead of captured mutable state
        let result1 = await Task(executorPreference: e1) { 1 }.value
        let result2 = await Task(executorPreference: e2) { 2 }.value

        #expect(result1 == 1)
        #expect(result2 == 2)

        pool.shutdown()
    }
}
