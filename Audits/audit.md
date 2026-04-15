# Audit: swift-executors

## Supervisor Review Findings — 2026-04-15

Verification of 10 supervisor review findings (L3 scope: findings 1–6).

| # | Original Finding | Location | Status |
|---|------------------|----------|--------|
| 1 | Stealing ABBA deadlock — `trySteal()` inside own `wait.withLock` | Kernel.Thread.Executor.Stealing.swift:118–148 | RESOLVED — lock scopes are separated. Own lock (line 121) released before steal loop (lines 127–133). Steal acquires only victim's lock. No simultaneous lock holding. |
| 2 | Polling `#if !os(Windows)` hides type | Kernel.Thread.Executor.Polling.swift:6 | OPEN — entire type behind `#if !os(Windows)`. See Code Surface finding #6 and Platform finding #2. |
| 3 | Polling run loop never blocks | Kernel.Thread.Executor.Polling.swift:122–129 | OPEN — run loop delegates blocking to `tick()` closure by contract (documented at init line 48: "a non-blocking tick will busy-spin"). No `waitSource.wait()` in the run loop itself. Design choice, not defect — but a footgun if consumer omits the blocking call. |
| 4 | Scheduled enqueues under lock | Executor.Scheduled.swift:92–118 | RESOLVED — `base.enqueue()` is outside the lock (lines 113–115). Comment at line 112: "Enqueue outside the lock". |
| 5 | Scheduled missing TaskExecutor conformance | Executor.Scheduled.swift:52–56 | RESOLVED — conditional `TaskExecutor where Base: TaskExecutor` conformance present. |
| 6 | Missing Executor.Main test | Executor.Main Tests.swift | RESOLVED — test exists (verifies `Main.shared.asUnownedSerialExecutor()` identity). Minimal but present. |

---

## Code Surface — 2026-04-15

### Scope

- **Target**: swift-executors (Executors target)
- **Skill**: code-surface — [API-NAME-*], [API-ERR-*], [API-IMPL-*]
- **Files**: 10 source files, 7 test files

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | MEDIUM | [API-NAME-002] | Kernel.Thread.Executor.Polling.swift:112 | `shutdownNow()` is compound identifier. Other executors use `shutdown()` — naming is inconsistent and the `Now` adds no semantic value (all shutdowns are immediate). | OPEN |
| 2 | MEDIUM | [API-NAME-002] | Executor.Cooperative.swift:66 | `shutdownNow()` — same compound identifier issue as #1 | OPEN |
| 3 | MEDIUM | [API-NAME-002] | Executor.Main.swift:85 | `shutdownNow()` — same compound identifier issue as #1 | OPEN |
| 4 | LOW | [API-NAME-002] | Executor.Wait.Condvar.swift:55 | `wakeAll()` is compound identifier. Nested form: `wake.all()`. Mitigated: single-use passthrough to `sync.broadcast()`. | OPEN |
| 5 | MEDIUM | [API-NAME-002] | Executor.Main.swift:73 | `runMainLoop()` is compound identifier. Should be `run()` (like `Executor.Cooperative.run()`). | OPEN |
| 6 | MEDIUM | [API-IMPL-005] | Kernel.Thread.Executor.swift:46–51 | `Mode` enum declared inside class body. Should be in `Kernel.Thread.Executor.Mode.swift`. | OPEN |
| 7 | MEDIUM | [API-IMPL-005] | Kernel.Thread.Executor.Polling.swift:26–30 | `Outcome` enum declared inside class body. Should be in `Kernel.Thread.Executor.Polling.Outcome.swift`. | OPEN |
| 8 | HIGH | [API-IMPL-005] | Kernel.Thread.Executor.Stealing.swift | Three type declarations in one file: `Stealing` (line 18), `Options` (line 41), `Worker` (line 90). `Options` and `Worker` each need their own file. Contrast: `Sharded.Options` IS correctly in a separate file. | OPEN |

### Summary

8 findings: 0 critical, 1 high, 6 medium, 1 low.

Namespace structure follows Nest.Name throughout ([API-NAME-001]). Spec-mirroring not applicable. Typed throws used where throwing ([API-ERR-001] — `Condvar.withLock` propagates `throws(E)`). The systemic pattern is compound identifiers on shutdown/wake methods and file organization for nested types in Stealing.

---

## Implementation — 2026-04-15

### Scope

- **Target**: swift-executors (Executors target)
- **Skill**: implementation — [IMPL-*], [PATTERN-*]
- **Files**: 10 source files

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | LOW | [IMPL-002] | Kernel.Thread.Executor.Sharded.swift:66 | `UInt64(Int(self.count))` — double type conversion exposes mechanism. `count` is `Kernel.Thread.Count` (typed); conversion chain to `UInt64` for modular arithmetic is an infrastructure gap. | OPEN |

### Summary

1 finding: 0 critical, 0 high, 0 medium, 1 low.

Run loops read as intent ([IMPL-INTENT]). No unnecessary intermediate bindings ([IMPL-EXPR-001]). `unsafe` keyword placement correct throughout — always wraps entire expression from left ([IMPL-034]). All executor types are classes (required by `SerialExecutor`/`TaskExecutor` protocol conformance) — `~Copyable` default ([IMPL-064]) not applicable. Isolation hierarchy ([IMPL-069]) correctly places executors at Rank 4/5 — they ARE the synchronization mechanism.

---

## Memory Safety — 2026-04-15

### Scope

- **Target**: swift-executors (Executors target)
- **Skill**: memory-safety — [MEM-SAFE-*], [MEM-SEND-*], [MEM-COPY-*]
- **Files**: 10 source files

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | MEDIUM | [MEM-SAFE-024] | (7 types) | Missing `@unsafe` on `@unchecked Sendable` conformances. All are Category A (synchronized via Condvar/Mutex). Affected: `Kernel.Thread.Executor`, `.Polling`, `.Stealing`, `.Stealing.Worker`, `Executor.Cooperative`, `.Main`, `.Scheduled`. | OPEN |
| 2 | LOW | [MEM-SAFE-024] | (7 types) | Missing safety invariant documentation on `@unchecked Sendable` conformances. Each should document the synchronization mechanism (e.g., "Internal `Condvar` serializes all access to `jobs` queue."). | OPEN |

### Summary

2 findings: 0 critical, 0 high, 1 medium, 1 low.

`Kernel.Thread.Executor.Sharded` correctly uses plain `Sendable` (not `@unchecked`) — all stored properties are Sendable ([MEM-SEND-004]). Strict memory safety enabled ([MEM-SAFE-001]). Individual `unsafe` acknowledgments present on all unsafe operations ([MEM-SAFE-002]). No `@unsafe` needed on the types themselves — they encapsulate safety via ecosystem types (Condvar, Queue, Flag), not raw pointers ([MEM-SAFE-021]).

---

## Platform — 2026-04-15

### Scope

- **Target**: swift-executors (Executors target)
- **Skill**: platform — [PLAT-ARCH-*], [PATTERN-*]
- **Files**: 10 source files, Package.swift

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | MEDIUM | [PLAT-ARCH-008] | Executor.Main.swift:7–8 | `import Dispatch` on Darwin bypasses the platform stack. Consumer-facing package should use `import Kernel` exclusively. Dispatch integration should live in a platform package or be abstracted behind the Kernel re-export chain. | OPEN |
| 2 | MEDIUM | [PLAT-ARCH-008a] | Kernel.Thread.Executor.Polling.swift:6 | `#if !os(Windows)` hides entire type. Domain authority criteria: (1) domain authority YES, (2) Kernel imports only YES (within the guarded block), (3) domain strategy YES, (4) irreducible YES — type requires non-Windows kernel events. Compliant as domain authority exception, but the namespace `Kernel.Thread.Executor.Polling` is invisible on Windows, preventing future IOCP-based implementation without source-breaking change. | OPEN |

### Summary

2 findings: 0 critical, 0 high, 2 medium, 0 low.

Swift 6 settings correctly configured ([PATTERN-005], [PATTERN-006]). Platform conditionals in `Executor.Main` use `#if os(...)` for platform identity ([PATTERN-004a]). The `import Dispatch` is the only bypass of the platform stack — all other platform access goes through `import Kernel`.
