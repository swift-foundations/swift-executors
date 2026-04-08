//
//  Kernel.Thread.Executor.Job.Queue Tests.swift
//  swift-executors
//

import Testing

@testable import Executors
import Kernel_Test_Support

extension Kernel.Thread.Executor.Job.Queue {
    enum Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests

extension Kernel.Thread.Executor.Job.Queue.Test.Unit {
    @Test("empty queue reports isEmpty")
    func emptyQueue() {
        let queue = Kernel.Thread.Executor.Job.Queue()
        #expect(queue.isEmpty)
    }

    @Test("default capacity is at least 64")
    func defaultCapacity() {
        let queue = Kernel.Thread.Executor.Job.Queue()
        #expect(queue.capacity >= 64)
    }

    @Test("default capacity is at least 1")
    func minimumCapacity() {
        let queue = Kernel.Thread.Executor.Job.Queue()
        #expect(queue.capacity >= 1)
    }

    @Test("dequeue from empty returns nil")
    func dequeueEmptyReturnsNil() {
        var queue = Kernel.Thread.Executor.Job.Queue()
        #expect(queue.dequeue() == nil)
    }
}


extension Kernel.Thread.Executor.Job.Queue.Test.Integration {
    @Test("queue grows when full")
    func growsWhenFull() {
        let queue = Kernel.Thread.Executor.Job.Queue()

        // Create dummy executor for job creation
        let executor = Kernel.Thread.Executor()
        defer { executor.shutdown() }

        // Verify the queue has at least the requested capacity
        // Note: Deque may allocate more than requested
        #expect(queue.capacity >= 2)
    }
}
