//
//  Executor.Cooperative Tests.swift
//  swift-executors
//

import Testing

@testable import Executors

extension Executor.Cooperative {
    enum Test {
        @Suite struct Unit {}
        @Suite struct Integration {}
    }
}

/// Actor pinned to a cooperative executor for enqueue-via-actor tests.
private actor Cooperator {
    nonisolated let cooperative: Executor.Cooperative
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        cooperative.asUnownedSerialExecutor()
    }

    var value: Int = 0

    init(_ cooperative: Executor.Cooperative) {
        self.cooperative = cooperative
    }

    func increment() { value += 1 }
}

// MARK: - Unit Tests

extension Executor.Cooperative.Test.Unit {
    @Test("create and shutdown")
    func createAndShutdown() {
        let executor = Executor.Cooperative()
        executor.shutdown()
    }

    @Test("stop without prior run is a no-op")
    func stopWithoutRun() {
        let executor = Executor.Cooperative()
        executor.stop()
        executor.shutdown()
    }

    @Test("runUntil returns immediately when condition is already true")
    func runUntilImmediateReturn() {
        let executor = Executor.Cooperative()
        executor.runUntil { true }
        executor.shutdown()
    }
}

// MARK: - Donation Contract

extension Executor.Cooperative.Test.Integration {
    @Test("run returns on shutdown from another thread")
    func runReturnsOnShutdown() async {
        let executor = Executor.Cooperative()

        let thread = Kernel.Thread.Handle.Reference(
            Kernel.Thread.trap { executor.run() }
        )

        try? await Task.sleep(for: .milliseconds(50))
        executor.shutdown()
        thread.join()
    }

    @Test("stop causes run to return")
    func stopCausesRunToReturn() async {
        let executor = Executor.Cooperative()

        let thread = Kernel.Thread.Handle.Reference(
            Kernel.Thread.trap { executor.run() }
        )

        try? await Task.sleep(for: .milliseconds(50))
        executor.stop()
        thread.join()

        // Executor is still usable after stop (non-destructive)
        executor.shutdown()
    }

    @Test("stop from another thread causes runUntil to return")
    func stopFromOtherThread() async {
        let executor = Executor.Cooperative()

        let thread = Kernel.Thread.Handle.Reference(
            Kernel.Thread.trap { executor.runUntil { false } }
        )

        try? await Task.sleep(for: .milliseconds(50))
        executor.stop()
        thread.join()
        executor.shutdown()
    }

    @Test("actor method runs on donated thread")
    func actorMethodRunsOnDonatedThread() async {
        let executor = Executor.Cooperative()
        let helper = Cooperator(executor)

        let thread = Kernel.Thread.Handle.Reference(
            Kernel.Thread.trap { executor.run() }
        )

        try? await Task.sleep(for: .milliseconds(50))

        await helper.increment()
        let result = await helper.value
        #expect(result == 1)

        executor.shutdown()
        thread.join()
    }

    @Test("shutdown dominates stop")
    func shutdownDominatesStop() async {
        let executor = Executor.Cooperative()

        let thread = Kernel.Thread.Handle.Reference(
            Kernel.Thread.trap { executor.run() }
        )

        try? await Task.sleep(for: .milliseconds(50))

        executor.stop()
        executor.shutdown()
        thread.join()
    }
}
