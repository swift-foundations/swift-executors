# Embedded Swift Scoping

<!--
---
version: 0.1.0
last_updated: 2026-04-16
status: IN_PROGRESS
tier: 2
---
-->

## Context

`swift-executors` v1 ships seven named compositions plus a base
executor. Embedded Swift is a growing deployment target — Wasm, ARM
Cortex-M, RP2040/RP2350, ESP32 (RISC-V), NuttX RISC-V. Not all
compositions can ship to all targets; this note scopes which can,
which cannot, and what guards are needed.

Embedded Swift's concurrency story is not yet SE-standardized. The
current integration point is the `Impl` hook-function C API (per
swift-evolution PR #2654: "it will still be possible to implement an
executor for Embedded Swift by implementing the `Impl` functions in
C/C++"). Wasm is the only Embedded target shipping concurrency by
default (`CooperativeExecutor` as both main and default executor);
MCU ports require user-built `_Concurrency` with a custom executor
[Verified: 2026-04-16 from CMakeLists.txt:336–348,
PlatformExecutorNone.swift:18–19, and Swift Forums posts by Max
Desiatov (2025-08-19, t/74515) and Rauhul Varma (2026-04-04,
t/85777)].

This document reaches `DECISION` when each of the eight compositions
has a locked ship/no-ship verdict with the `#if` guard strategy
documented.

**Post-review note (2026-04-16):** Wasm with SharedArrayBuffer gives
real multithreading to wasm32, and the stdlib ships
`Synchronization.Mutex` for wasm32 (`CMakeLists.txt:198–200`). Thread-
based executors could be SHIP (not just CONDITIONAL) on threaded Wasm
— contingent on `Kernel.Thread` having a Wasm-threads backend. Tracked
as a separate prerequisite, not resolved here.

## Question

For each executor in the v1 taxonomy, determine:

1. **Ship viability.** Can it compile and be meaningful on Embedded Swift
   targets?
2. **Guard strategy.** What `#if` guards are required?
3. **Degradation.** If the full composition is unavailable, is there a
   subset that ships?

## Constraints

| Constraint | Source | Implication |
|------------|--------|-------------|
| `@_unavailableInEmbedded`: `TaskExecutor`, `globalConcurrentExecutor`, `Task.currentExecutor`, `ContinuousClock`, `SuspendingClock`, `Task.sleep`, all `ExecutorAssertions` | `Executor.swift`, `ContinuousClock.swift`, `SuspendingClock.swift`, `TaskSleep.swift`, `ExecutorAssertions.swift` [Verified: 2026-04-16] | Embedded has no clocks, no `Task.sleep`, no `TaskExecutor` |
| `SchedulingExecutor` `enqueue<C: Clock>` overloads gated `#if !$Embedded` | `Executor.swift:66, 109` [Verified: 2026-04-16] | Embedded cannot conform to `SchedulingExecutor`; SE-0505 states: "We will not be able to support the new Clock-based enqueue APIs on Embedded Swift at present because it does not allow protocols to contain generic functions" |
| `ManagedBuffer` available on Embedded but requires heap | `ManagedBuffer.swift:48–84, 298, 695` [Verified: 2026-04-16] | Chase-Lev heap variant works on Embedded-with-heap; `.Static<N>` variant (inline) is the no-heap option |
| `Synchronization.Atomic<T>` ships on Embedded; `Synchronization.Mutex` does NOT (except wasm32) | `CMakeLists.txt:127–228`, `MutexUnavailable.swift:34` [Verified: 2026-04-16] | Any code using `Mutex<State>` must be `#if !$Embedded` gated or replaced with atomic-only lock |
| `pthread_*` / `kqueue` / `epoll` / `io_uring` / `libdispatch` not available on MCU targets | `Kernel.Thread.Handle.swift:20–21`, swift-executor-primitives `Package.swift:130–134` (`KERNEL_AVAILABLE` excludes embedded platforms) [Verified: 2026-04-16] | All `Kernel.Thread.Executor.*` and `Executor.Main` are OS-dependent |
| `swift-executors/Package.swift` lists only `[.macOS(.v26), .iOS, .tvOS, .watchOS, .visionOS]` | `Package.swift:7–13` [Verified: 2026-04-16] | No Embedded or Linux platform declared; nothing is Embedded-gated today |
| Embedded default executors: `CooperativeExecutor` on wasm32; `UnimplementedMainExecutor`/`UnimplementedTaskExecutor` (fatalError) elsewhere | `CMakeLists.txt:336–348`, `PlatformExecutorNone.swift:18–19`, `UnimplementedExecutor.swift` [Verified: 2026-04-16] | Non-wasm Embedded users must install their own factory via `_createExecutors(factory:)` |
| `ExecutorJob` / `UnownedJob` exist on Embedded; `runSynchronously(on: UnownedSerialExecutor)` is available; `UnownedTaskExecutor` overloads are `@_unavailableInEmbedded` | `PartialAsyncTask.swift:62, 124, 145, 173, 404` [Verified: 2026-04-16] | Our executors that use only `SerialExecutor`-based dispatch can work; `TaskExecutor` conformance must be `#if` gated |
| No Embedded-specific SE proposal for concurrency; vision doc (`embedded-swift.md`) has zero mentions of concurrency/executor | `swift-evolution/visions/embedded-swift.md` [Verified: 2026-04-16] | Embedded concurrency is de-facto but not de-jure |

## Analysis

### Per-Composition Verdicts

| Composition | Threads | Atomics | Heap | Event Src | Clock | Verdict |
|-------------|:---:|:---:|:---:|:---:|:---:|---------|
| `Kernel.Thread.Executor` | yes | yes | yes | — | — | CONDITIONAL |
| `…Polling` | yes | yes | yes | epoll/kqueue | — | NO |
| `…Completion` | yes | yes | yes | io_uring | — | NO |
| `…Sharded` | yes (N) | yes | yes | — | — | CONDITIONAL |
| `…Stealing` | yes (N) | yes | yes | — | — | CONDITIONAL |
| `Executor.Scheduled<Base>` | yes (timer) | yes | yes | — | `ContinuousClock` | NO on Embedded (clock unavailable) |
| `Executor.Cooperative` | **no** | yes | yes | — | — | SHIP-WITH-GUARDS |
| `Executor.Main` | yes | yes | yes | libdispatch | — | NO |

#### NO: `Polling`, `Completion`, `Main`

These depend on host-OS kernel primitives (epoll/kqueue, io_uring,
libdispatch) that have no MCU equivalent. No degradation path exists —
the entire abstraction is meaningless on bare metal.

**Guard:** already gated by `#if !os(Windows)` (Polling) or
platform-specific imports. No Embedded guard needed because these
targets can never be selected by the SwiftPM platform list.

#### NO: `Executor.Scheduled<Base>`

Depends on `ContinuousClock` (`@_unavailableInEmbedded`) for deadlines
and on `Executor.Wait.Condvar` (built on `pthread_cond_t`) for the
timer thread's timed wait. Neither is available on Embedded.

A future Embedded-compatible variant could use a hardware-timer backend
instead of `ContinuousClock` + condvar, but this is a different
executor, not a `#if` guard over the existing one.

`SchedulingExecutor` conformance — the v1 recommendation from
`scheduled-executor-policy.md` — is additionally impossible on Embedded
because the protocol's `enqueue<C: Clock>` overloads are `#if !$Embedded`
gated in stdlib. This is consistent: the executor that cannot schedule
also cannot conform to the scheduling protocol.

#### CONDITIONAL: `Kernel.Thread.Executor`, `Sharded`, `Stealing`

These require OS threads (`Kernel.Thread.trap` → `pthread_create`) and
`Executor.Wait.Condvar` (`pthread_cond_t`). They work on
Embedded-with-threads (FreeRTOS, Zephyr, NuttX) if `Kernel.Thread` has
an RTOS backend. They do not work on bare-metal single-core targets.

Today, `swift-executor-primitives` gates all thread-dependent code
behind `KERNEL_AVAILABLE`, which excludes Embedded platforms.
Enabling these on Embedded-with-threads requires:

1. An RTOS-backed `Kernel.Thread` implementation (FreeRTOS xTaskCreate,
   Zephyr k_thread_create) — a platform-layer (L2) concern.
2. A `Kernel.Thread.Mutex` / `Kernel.Thread.Condition` using RTOS
   primitives instead of `pthread_mutex_t` / `pthread_cond_t`.
3. Adding the RTOS platform to the `KERNEL_AVAILABLE` define in
   `swift-executor-primitives/Package.swift:130–134`.

These are prerequisites in `swift-kernel-primitives`, not in
`swift-executors`. Deferred to the platform-kernel RTOS initiative.

**Sharded and Stealing** additionally assume multi-core, which is
available on RP2040 (dual Cortex-M0+), ESP32-S3 (dual Xtensa), and
multi-core RISC-V — but not on single-core Cortex-M0. Meaningfulness
is hardware-dependent; a shard count of 1 degrades to the base
executor, which is fine.

#### SHIP-WITH-GUARDS: `Executor.Cooperative`

No OS thread spawned; runs on the caller's thread. Depends on:

- `Executor.Job.Queue` (heap `Deque<UnownedJob>`) — needs heap
  allocation. Could be retargeted to a bounded ring buffer for
  `-no-allocations` Embedded, but that is a v2 concern.
- `Executor.Wait.Condvar` — used for blocking `run()` wait. On
  single-threaded Embedded, the condvar reduces to a no-op (or
  hardware WFI). Needs a `#if $Embedded` alternate `Wait` backend
  (interrupt-disable + WFI loop).
- `Synchronization.Atomic` — ships on Embedded. No issue.
- `SerialExecutor` conformance — available on Embedded. No issue.
- `TaskExecutor` conformance — `@_unavailableInEmbedded`. Must be
  `#if !$Embedded` gated on the conformance extension.
- `SchedulingExecutor` conformance — the stdlib protocol's
  `enqueue<C: Clock>` overloads are `#if !$Embedded`. If the
  `scheduled-executor-policy.md` recommendation (conform) is
  implemented, the conformance extension must also be gated.

**Minimum viable Embedded Cooperative executor** (v1):
- `SerialExecutor` conformance only (no `TaskExecutor`, no
  `SchedulingExecutor`)
- Bounded job queue (if no-heap target)
- `Wait` backend: busy-wait or WFI (no condvar)
- `run()` loop: drain jobs, WFI when empty

This matches the stdlib's own `CooperativeExecutor` on wasm32
(`CooperativeExecutor.swift:161`) — which is the proven pattern.

### Cross-Cutting: `TaskExecutor` on Embedded

`TaskExecutor` is `@_unavailableInEmbedded`. Every executor in our
taxonomy that conforms to `TaskExecutor` must gate that conformance:

```swift
#if !$Embedded
extension Kernel.Thread.Executor.Polling: TaskExecutor { ... }
#endif
```

This affects: `Polling`, `Sharded`, `Stealing`, `Scheduled` (all
have conditional `TaskExecutor` conformances). Only `Cooperative`
and the base `Kernel.Thread.Executor` ship with `SerialExecutor`
alone as a viable Embedded surface.

### Cross-Cutting: Priority Escalation on Embedded

Per `priority-escalation-policy.md` v0.3.0, M3 (thread QoS bump) is
Darwin-only. Embedded has no QoS concept. The recommendation "M3
off by default" inherently degrades to "no priority tracking on
Embedded." No additional guard needed — M3 is already platform-gated.

## Outcome

**Status:** `IN_PROGRESS`.

### Initial recommendations

| Composition | Verdict | Guard strategy |
|-------------|---------|---------------|
| `Polling` | NO | Already platform-gated |
| `Completion` | NO | Already platform-gated |
| `Main` | NO | Already platform-gated |
| `Scheduled` | NO | Gate on `ContinuousClock` availability; `SchedulingExecutor` conformance gated by `#if !$Embedded` |
| `Kernel.Thread.Executor` | CONDITIONAL | Deferred to RTOS `Kernel.Thread` backend |
| `Sharded` | CONDITIONAL | Same prerequisite as base |
| `Stealing` | CONDITIONAL | Same prerequisite as base |
| `Cooperative` | SHIP-WITH-GUARDS | `TaskExecutor`/`SchedulingExecutor` conformances `#if !$Embedded`; `Wait` backend needs Embedded alternative |

### Rationale summary

1. Only `Cooperative` can ship to Embedded in v1. It is the stdlib's
   own pattern (`CooperativeExecutor` on wasm32).
2. Thread-based executors are CONDITIONAL on RTOS `Kernel.Thread` — a
   platform-layer prerequisite, not a swift-executors concern.
3. `Polling`, `Completion`, `Main` are inherently host-OS-only.
4. `Scheduled` is blocked by `ContinuousClock` unavailability on
   Embedded — a stdlib constraint, not ours.
5. `TaskExecutor` conformances must be `#if !$Embedded` gated across
   the board.

### Next steps before promotion to DECISION

1. **Audit every `TaskExecutor` conformance** in swift-executors source
   and add `#if !$Embedded` guards. Low-cost, can be done immediately.
2. **Design the Embedded `Wait` backend** for `Cooperative` — either
   `#if $Embedded` busy-wait or a trait-based wait-strategy that
   accepts a platform-provided WFI closure. Decide which.
3. **Coordinate with `cooperative-donation-contract.md`** — the
   donation contract for `runUntil` shapes the Embedded `Cooperative`
   surface. That note needs to declare whether the Embedded variant
   drops `runUntil` or implements it with busy-wait.
4. **Track RTOS `Kernel.Thread` backend** as a separate research
   topic in `swift-kernel-primitives` (not this document). When that
   lands, re-evaluate CONDITIONAL compositions.
5. **Track stdlib Embedded concurrency stabilization** — no SE
   proposal exists yet. When one arrives, re-evaluate all verdicts.

### Escalation note

Per [RES-004b]: this analysis touches `swift-executor-primitives` (L1)
for `KERNEL_AVAILABLE` gating, `swift-executors` (L3) for per-
composition verdicts, and `swift-kernel-primitives` (L1) for the RTOS
thread prerequisite. Scope is cross-package across `swift-foundations`
+ `swift-primitives`. No escalation to `swift-institute` required.

## References

### Stdlib Embedded gates (cited above)

- `swiftlang/swift` — `stdlib/public/Concurrency/Executor.swift:48, 66,
  109, 140, 187, 559–624, 733, 985–1014` (`#if !$Embedded` walls).
- `swiftlang/swift` — `stdlib/public/Concurrency/ContinuousClock.swift:24,
  60, 72, 136, 146`, `SuspendingClock.swift:24, 44, 56, 124, 134`
  (`@_unavailableInEmbedded`).
- `swiftlang/swift` — `stdlib/public/Concurrency/TaskSleep.swift:17`,
  `TaskSleepDuration.swift:16, 34, 77` (`@_unavailableInEmbedded`).
- `swiftlang/swift` — `stdlib/public/Concurrency/CooperativeExecutor.swift:100,
  163, 246, 294, 312` (`SchedulingExecutor` conformance gated
  `!$Embedded`).
- `swiftlang/swift` — `stdlib/public/Concurrency/CMakeLists.txt:336–348`
  (Embedded executor platform selection).
- `swiftlang/swift` — `stdlib/public/core/ManagedBuffer.swift:48–84`
  (`#if $Embedded` branches).
- `swiftlang/swift` — `stdlib/public/Synchronization/CMakeLists.txt:127–228`
  (Embedded builds: atomics yes, Mutex no except wasm32).

### Swift Evolution / Forums

- [SE-0505: Delayed Enqueuing for
  Executors](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0505-delayed-enqueuing.md)
  — "We will not be able to support the new Clock-based enqueue APIs on
  Embedded Swift."
- [swift-evolution PR #2654](https://github.com/swiftlang/swift-evolution/pull/2654)
  — "`Impl` functions in C/C++" as the Embedded integration point.
- Swift Forums t/74515 — John McCall (2024-11-25): "a lot of embedded
  environments are not concurrent in the threads sense"; Rauhul Varma
  (2024-09-12): "adapters for popular runtimes e.g. Zephyr, FreeRTOS";
  Max Desiatov (2025-08-19): "Concurrency is now supported in Embedded
  Swift for Wasm."
- Swift Forums t/85777 — Rauhul Varma (2026-04-04): on-demand stdlib
  builds via SwiftPM in progress.
- Swift Forums t/83834 — orobio (2026-02-11): working STM32
  NUCLEO-F411RE concurrency with custom `GlobalExecutor.swift`.
- [apple/swift-embedded-examples](https://github.com/apple/swift-embedded-examples)
  — STM32, RP2040/RP2350, ESP32-C6, NuttX RISC-V, Wasm, Playdate.

### Internal references

- `executor-package-design.md` — locked taxonomy.
- `priority-escalation-policy.md` v0.3.0 — M3 is Darwin-only; inherently
  degrades on Embedded.
- `scheduled-executor-policy.md` — `SchedulingExecutor` conformance
  recommendation is `#if !$Embedded` by construction.
- `cooperative-donation-contract.md` (pending) — shapes the Embedded
  `Cooperative` surface.
