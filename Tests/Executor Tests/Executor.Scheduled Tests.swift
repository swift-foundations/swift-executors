//
//  Executor.Scheduled Tests.swift
//  swift-executors
//

// ⚠️ W5 QUARANTINE (2026-06-12): sympathetic consumer carve — the producer
// parked Executor Job Priority Primitives (Job.Priority stores Heap<Entry>;
// heap's umbrella pulls the RED memory-small module; see executor-primitives
// Package.swift:33). Executor.Scheduled is carved with it, so its suite is
// carved too. Carved per Ruling 2 / lane-λ in
// .handoffs/HANDOFF-sockets-restoration-kernel-blocker.md.
// Restore with heap's round.

// import Testing
// import Executors

// @Suite
// struct ScheduledTests {
//     @Test
//     func `scheduled wraps base executor`() {
//         let base = Kernel.Thread.Executor()
//         let scheduled = Executor.Scheduled(base: base)
//         defer {
//             scheduled.shutdown()
//             base.shutdown()
//         }
//         _ = scheduled.asUnownedSerialExecutor()
//     }
// }
