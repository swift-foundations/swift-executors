# Audit: swift-executors

## Supervisor Review Findings — 2026-04-15

Verification of 10 supervisor review findings (L3 scope: findings 1–6).

| # | Original Finding | Location | Status |
|---|------------------|----------|--------|
| 1 | Stealing ABBA deadlock — `trySteal()` inside own `wait.withLock` | Kernel.Thread.Executor.Stealing.swift:118–148 | RESOLVED — lock scopes are separated. Own lock (line 121) released before steal loop (lines 127–133). Steal acquires only victim's lock. No simultaneous lock holding. |
| 2 | Polling `#if !os(Windows)` hides type | Kernel.Thread.Executor.Polling.swift:6 | DEFERRED 2026-04-16 — Executor Judgment Calls handoff (closed) declined remediation. Domain-authority exception per [PLAT-ARCH-008a] accepted; future Windows backend will ship as sibling `Kernel.Thread.Executor.IOCP`, not as a Polling backend, removing source-breaking-change concern. `// WHY:` + `// TRACKING:` comments present per [PATTERN-016]. See Platform finding #2. |
| 3 | Polling run loop never blocks | Kernel.Thread.Executor.Polling.swift:161–181 | RESOLVED 2026-04-15 — Phase 3a API revision (commit `e41aded`). Run loop now calls `waitSource.wait()` directly; tick signature changed to `(UnsafeBufferPointer<Kernel.Event>) -> Outcome` receiving events from the poll. Blocking is no longer the consumer's responsibility. |
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
| 1 | MEDIUM | [API-NAME-002] | Kernel.Thread.Executor.Polling.swift:145 | `shutdownNow()` is compound identifier. Other executors use `shutdown()` — naming is inconsistent and the `Now` adds no semantic value (all shutdowns are immediate). | RESOLVED 2026-04-15 — renamed to `shutdown()` with `isCurrent`-based join/detach logic. `IO.Event.Loop` updated to match. `Cooperative.shutdownNow()` and `Main.shutdownNow()` (findings #2, #3) still pending. |
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

## Implementation — 2026-04-16

### Scope

- **Target**: swift-executors (Executors target), post Executor Judgment Calls handoff closure
- **Skill**: implementation — [IMPL-002], [IMPL-010], [IMPL-050], [IMPL-INTENT]
- **Files**: 11 source files (current HEAD `c296df5`)

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | LOW | [IMPL-002] | Kernel.Thread.Executor.Sharded.swift (previous :66) | Original 2026-04-15 finding: `UInt64(Int(self.count))` double conversion for round-robin modular arithmetic. | RESOLVED 2026-04-15 — commit `1529eea` replaced with `Atomic<Index<Kernel.Thread>>.advance(within: count)`. Current site (`next()` at :66): `executors[cursor.advance(within: count)]` — typed throughout. |
| 2 | MEDIUM | [IMPL-002] | Kernel.Thread.Executor.Sharded.swift:75–77 | `public func executor(at index: Int) -> Kernel.Thread.Executor { executors[index % executors.count] }` — parameter is raw `Int` on a type whose internal position is `Index<Kernel.Thread>`; body uses `Int` modulo against `executors.count` (also `Int`). Typed form: `public func executor(at position: Index<Kernel.Thread>) -> Kernel.Thread.Executor` with the existing `cursor.advance(within: count)` pattern or modular reduction on the typed position. | DEFERRED 2026-04-16 — Executor Judgment Calls handoff explicitly declared out of original 4 sites (typed count adoption scope); flagged for follow-up. Fix is source-breaking (public signature change). |
| 3 | MEDIUM | [IMPL-002] | Kernel.Thread.Executor.Stealing.swift:64 | `Worker(id: Int(bitPattern: position.ordinal))` — extracts raw `Ordinal` via `.ordinal` accessor, converts to `Int` via `bitPattern` because `Worker.id` is typed `Int`. The conversion at the call site is the symptom; the root cause is `Worker.id`'s type. | RESOLVED 2026-04-17 — `Worker.id` retyped to `Index<Kernel.Thread>`; call site now `Worker(id: position)` with no `Int(bitPattern:)` conversion. |
| 4 | MEDIUM | [IMPL-002] | Kernel.Thread.Executor.Stealing.Worker.swift:33, :38, :69–70 | Root cause for findings #3 and downstream arithmetic: `let id: Int` (:33), `init(id: Int)` (:38), and the stealing loop `for offset in 1..<pool.workers.count { let victim = (id + offset) % pool.workers.count }` (:69–70). The steal loop reads as mechanism — raw `Int` arithmetic against an array `.count`, modular reduction for victim selection, bare `Range<Int>` iteration. Typed form: `id: Index<Kernel.Thread>`; offset iteration via a typed range or `forEach` over a `Cardinal`-derived count; victim selection via `(id + offset).retag` composed with `cursor`-style typed modular reduction. Infrastructure (`Ordinal.Protocol % Cardinal.Protocol`, `Array(count:)`) exists in scope via `Ordinal_Primitives` / `Index_Primitives` already imported. | RESOLVED 2026-04-17 — `Worker.id: Index<Kernel.Thread>` and `init(id: Index<Kernel.Thread>)`; XorShift32 seed reads `id.ordinal.rawValue`; steal loop uses typed `Cardinal`/`Ordinal` arithmetic (`count > .one`, `count.subtract.saturating(.one)`, `Index<Kernel.Thread>(Ordinal(UInt(nextRandom()))) % count`, `victim + .one`, `attempts += .one`). 32/32 tests pass. |

### Summary

4 findings: 0 critical, 0 high, 3 medium, 1 low. 3 RESOLVED, 1 DEFERRED.

Findings #2, #3, #4 are the "remaining tasks" from the Executor Judgment Calls handoff closure. All were explicitly flagged for follow-up, not silently deferred — handoff closure reflection (`2026-04-15-executor-judgment-calls-handoff-closure.md`, action item #3) names the two root sites; this audit adds the Worker cascade (#4) that was not enumerated in the closure.

The root-cause analysis for #3/#4 — `Worker.id` is the axis of the mechanism leak — was acted on 2026-04-17: a standalone retype to `Index<Kernel.Thread>` resolved both in one ~50-line change (HANDOFF-worker-id-typed-retype.md). The Chase-Lev research direction stays open as a separate, larger refactor. Finding #2 (`Sharded.executor(at index: Int)`) is unaffected by the Worker retype — its public-API signature change remains DEFERRED.

Run loops read as intent ([IMPL-INTENT]). No unnecessary intermediate bindings ([IMPL-EXPR-001]). `unsafe` keyword placement correct throughout ([IMPL-034]). All executor types are classes (required by `SerialExecutor`/`TaskExecutor`) — `~Copyable` default ([IMPL-064]) not applicable. Isolation hierarchy ([IMPL-069]) correctly places executors at Rank 4/5.

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

## Platform — 2026-04-16

### Scope

- **Target**: swift-executors (Executors target), post Executor Judgment Calls handoff closure
- **Skill**: platform — [PLAT-ARCH-*], [PATTERN-*]
- **Files**: 11 source files, Package.swift (current HEAD `c296df5`)

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | MEDIUM | [PLAT-ARCH-008] | Executor.Main.swift:7–8 | `import Dispatch` on Darwin bypasses the platform stack. Consumer-facing package should use `import Kernel` exclusively. Dispatch integration should live in a platform package or be abstracted behind the Kernel re-export chain. | OPEN |
| 2 | MEDIUM | [PLAT-ARCH-008a] | Kernel.Thread.Executor.Polling.swift:6 | `#if !os(Windows)` hides entire type. Domain authority criteria: (1) domain authority YES, (2) Kernel imports only YES (within the guarded block), (3) domain strategy YES, (4) irreducible YES — type requires non-Windows kernel events. Namespace `Kernel.Thread.Executor.Polling` is invisible on Windows. | DEFERRED 2026-04-16 — Executor Judgment Calls handoff (closed) declined remediation. Supervisor rationale: future Windows backend will ship as sibling `Kernel.Thread.Executor.IOCP`, not as a Polling backend, so the source-breaking-change concern that Ground Rule #4 of the original executor dispatch hedged against is moot. Original Ground Rule #4 superseded by later domain-authority analysis. `// WHY:` + `// TRACKING:` comments present in file per [PATTERN-016]. |

### Summary

2 findings: 0 critical, 0 high, 2 medium, 0 low. 1 OPEN, 1 DEFERRED.

Swift 6 settings correctly configured ([PATTERN-005], [PATTERN-006]). Platform conditionals in `Executor.Main` use `#if os(...)` for platform identity ([PATTERN-004a]). The `import Dispatch` is the only bypass of the platform stack — all other platform access goes through `import Kernel`.

---

## Code Surface — 2026-04-17

> **Verification (per [SUPER-011])**: Ground rules respected — #1 (audited only files enumerated under `## Relevant Files`); #2 (pre-existing dated sections in `Audits/audit.md` left byte-for-byte unchanged, only appended new sections); #3 (no benchmark sources under `Experiments/*/` audited); #4 (L1 findings use absolute paths under `/Users/coen/Developer/swift-primitives/`); #5 (cross-referenced prior dated sections rather than duplicating); #6 (no findings require commit reversion — none escalated).

### Scope

- **Target**: swift-executors (Executors target) + L1 companion work in swift-executor-primitives and swift-cpu-primitives
- **Skill**: code-surface — [API-NAME-*], [API-ERR-*], [API-IMPL-*]
- **Files** (session commits `e53ca62`, `8dc134a`, `7ca7240`): 9 source files in swift-executors, 3 source files in swift-primitives. Test files listed in the brief are out of scope per [AUDIT-012] (non-testing skill audit covers source files only).

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | MEDIUM | [API-IMPL-008] | Kernel.Thread.Executor.Stealing.Worker.swift:32–138 | The `Worker` class body contains seven methods (`nextRandom()`, `start(pool:)`, `enqueue(_:)`, `wake()`, `join()`, `runLoop(pool:)`, `trySteal()`) alongside its stored properties and canonical init. Per [API-IMPL-008], type bodies MUST contain only stored properties, canonical initializer(s), and `deinit`; methods belong in extensions. Sibling executor classes follow the rule (`Sharded.swift`, `Stealing.swift`, `Polling.swift` all keep methods in extensions). Session commit `7ca7240` added `nextRandom()` to the body, perpetuating the pre-existing pattern that file-split commit `1529eea` did not normalize when extracting Worker from Stealing.swift (prior: Code Surface 2026-04-15 finding #8 addressed file separation but not internal organization). | RESOLVED 2026-04-17 — class body now holds only stored properties + canonical init; the seven methods moved to four grouped extensions (`PRNG`, `Lifecycle`, `Job Queue`, `Run Loop`) in the same file, preserving `private`/`fileprivate` access through Swift's same-file extension scope. 32/32 tests pass. |

### Summary

1 finding: 0 critical, 0 high, 1 medium, 0 low. 1 RESOLVED.

The new file `Kernel.Thread.Executor.PriorityOverride.swift` declares no new types — only `internal static` helpers in an extension on `Kernel.Thread.Executor`, plus one module-scope `_qosClass(for:)` helper guarded by `#if canImport(Darwin)`. The compound identifier `runJob` on the static helpers is permitted at the static-implementation layer per [IMPL-024] (and reinforced by [feedback_compound_package_scope]); the `_` prefix on `_qosClass` signals implementation-detail status per established Swift idiom. New `priorityTracking: Bool` parameters on `Sharded.Options`, `Stealing.Options`, `Polling.init`, and `Executor.init` are binary on/off configuration — boolean is appropriate per [API-IMPL-003] (no expanding state space).

`/Users/coen/Developer/swift-primitives/swift-cpu-primitives/Sources/CPU Primitives/CPU.Cache.Padded.swift` is fully [API-IMPL-008]-compliant: `Padded<T: ~Copyable>` body holds only `_storage`, `_byteCount`, the canonical `init`, and `deinit`; the `value` coroutine accessor and `Sendable` conformance live in extensions. The `@safe` attribute is documented with a `// WHY:` comment per [PATTERN-016].

`/Users/coen/Developer/swift-primitives/swift-executor-primitives/Sources/Executor Job Priority Primitives/Executor.Job.Priority.Entry.swift` and `Executor.Job.Priority.swift` keep type bodies minimal; the new `sequence: UInt64` field on `Entry` and `_nextSequence: UInt64` on `Priority` are ordinary stored properties.

The pre-existing findings #2–#8 from Code Surface 2026-04-15 (compound `shutdownNow`, `wakeAll`, `runMainLoop`; nested `Mode`/`Outcome` enums; three types in `Stealing.swift`) are not re-audited here — none of those locations were modified by session commits in scope.

---

## Implementation — 2026-04-17

> **Verification (per [SUPER-011])**: Ground rules respected — #1 (files enumerated only); #2 (no rewrites of prior sections); #3 (Experiments benchmarks excluded); #4 (L1 absolute paths used); #5 (prior sections cross-referenced); #6 (no revert-class findings).

### Scope

- **Target**: swift-executors session commits + L1 companion changes
- **Skill**: implementation — [IMPL-002], [IMPL-EXPR-001], [IMPL-023], [IMPL-024], [IMPL-034], [IMPL-INTENT], [PATTERN-016]
- **Files** (session commits `e53ca62`, `8dc134a`, `7ca7240`): 9 source files in swift-executors, 3 source files in swift-primitives.

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | MEDIUM | [IMPL-002] | Kernel.Thread.Executor.Stealing.Worker.swift:96–108 | Random-victim steal loop adds new raw-`Int` arithmetic at call sites: `let n = pool.workers.count` (pulls a raw `Int` from the array), `for _ in 0..<(n - 1)` (raw `Range<Int>`), `var victim = Int(nextRandom() % UInt32(n))` (raw modulo on `UInt32` then `Int`-narrow), `victim = (victim + 1) % n` (raw modular advance), and `pool.workers[victim]` indexing. Per [IMPL-002], modular arithmetic on a typed position should be expressed via the typed cursor pattern (`Cardinal % Cardinal → Ordinal`, `(id + offset).retag` etc.). This extends the cascade tracked in **prior: Implementation 2026-04-16 finding #4** (Worker.id raw `Int`, sequential steal loop). The deferral reasoning there — that the Chase-Lev work-stealing redesign may replace the Worker implementation wholesale — applies equally to this new arithmetic. | RESOLVED 2026-04-17 — fixed alongside prior 2026-04-16 finding #4 by Worker.id retype. Loop now reads `let count = pool.count`, gates on `count > .one`, walks `attempts < limit` where `limit = count.subtract.saturating(.one)`, samples `Index<Kernel.Thread>(Ordinal(UInt(nextRandom()))) % count`, advances on self-collision via `(victim + .one) % count`, and indexes `pool.workers[victim]` through the existing `Array.subscript<O: Ordinal.Protocol>` integration. No raw `Int` remains. 32/32 tests pass. |
| 2 | LOW | [IMPL-EXPR-001] | /Users/coen/Developer/swift-primitives/swift-executor-primitives/Sources/Executor Job Priority Primitives/Executor.Job.Priority.Entry.swift:51–57, :67–77 | Both operator overloads use single-use intermediate `let` bindings: `==` declares `lhsDeadline`, `rhsDeadline`, `lhsSequence`, `rhsSequence` (each used once); `<` declares `lhsDeadline`, `rhsDeadline` (used twice — multi-use exception applies) but also `lhsSequence`, `rhsSequence` (each used once). None hit the [IMPL-EXPR-001] boundary conditions (multi-use, explanatory name, complexity ceiling) for the single-use bindings. The intent-style form is `return lhs.deadline == rhs.deadline && lhs.sequence == rhs.sequence` and the equivalent for `<`. Borrowed-`self` access does not require the bindings; `borrowing` parameters permit direct property access for Copyable fields. | RESOLVED 2026-04-17 — replaced both bodies with tuple comparison: `(lhs.deadline, lhs.sequence) == (rhs.deadline, rhs.sequence)` and `< (rhs.deadline, rhs.sequence)`. Note: the naive `lhs.deadline == rhs.deadline && lhs.sequence == rhs.sequence` form fails the borrow checker on `borrowing Self` parameters (chained property access via `&&` flagged as consumption); tuple comparison sidesteps this by collecting both fields into a single non-short-circuit expression. The audit's "borrowed-self access does not require the bindings" rationale was incorrect for the naive `&&` form — corrected here. |

### Summary

2 findings: 0 critical, 0 high, 1 medium, 1 low. 0 OPEN, 2 RESOLVED.

`Kernel.Thread.Executor.PriorityOverride.swift` follows the [IMPL-023] static-layer pattern correctly: instance methods on `Executor`, `Polling`, and `Stealing.Worker` delegate to `Kernel.Thread.Executor.runJob(_:onSerial/onTask:priorityTracking:)`. `unsafe` keyword placement at lines :41, :44–45, :63, :66–67 wraps each expression from the left per [IMPL-034]. The Darwin/non-Darwin branches in `runJob` are appropriately split via `#if canImport(Darwin)` (the `pthread_override_qos_class_*` symbols are platform-bound). The `_qosClass(for:)` switch enumerates the five public Darwin QoS classes and returns `nil` for unmapped raw values — the boundary conversion (`UInt32(job.priority.rawValue)`) is necessary mechanism at the C-API edge.

`/Users/coen/Developer/swift-primitives/swift-cpu-primitives/Sources/CPU Primitives/CPU.Cache.Padded.swift` is well-implemented for L1 raw-pointer mechanism: `Swift.max(MemoryLayout<T>.stride, 128)` is the documented portable cache-line minimum (the `// WHY:` comments at :42–46 of `Sharded.swift` and :47–51 of `Padded.swift` explain the choice per [PATTERN-016]); `init` consumes `T` into the slot and `deinit` deinitializes-then-deallocates with the stored `_byteCount`; the `value` coroutine accessor yields directly from `_storage.pointee` for both `_read` and `_modify` so callers operate in place on the heap slot — this is the documented pattern for wrapping `~Copyable` atomics.

The new `_nextSequence: UInt64` counter on `Executor.Job.Priority` and the `sequence: UInt64` field on `Entry` implement deterministic FIFO tie-breaking within a deadline (Java `ScheduledThreadPoolExecutor` discipline). `schedule(_:at:)` reads-then-increments via `&+=` — wrap-around semantics are appropriate for a 64-bit monotonic counter (overflow at one entry per nanosecond would take ~584 years).

`Sharded.cursor: CPU.Cache.Padded<Atomic<Index<Kernel.Thread>>>` (Sharded.swift:46) and `next()`'s `executors[cursor.value.advance(within: count)]` (Sharded.swift:74) keep the typed Index<Kernel.Thread> position throughout the hot path — no `.rawValue` extraction at the call site. The `cursor.value.advance(within: count)` accessor chain composes cleanly through the Padded coroutine accessor and the Atomic typed-position API.

The new boolean `priorityTracking` parameters propagate through `Sharded.init` → per-shard `Executor.init`, `Stealing.init` → `Stealing.priorityTracking` → `Worker.runLoop` reads `pool.priorityTracking` per iteration. Reading the flag once per job rather than caching at Worker construction is intentional: `Stealing.Options` is a v1 surface with `false` default, and the v2 transition to `true`-by-default-on-Darwin will not require Worker-side changes.

The `try!` in `Sharded.Options.defaultCount` (Sharded.Options.swift:55) and `Stealing.Options.defaultCount` (Stealing.Options.swift:45) is acceptable — `Kernel.Thread.Count.init(4)` is a compile-time constant whose throwing path (zero count) is statically unreachable. This is not the `try?` anti-pattern called out by [feedback_prefer_typed_throws_over_try_optional].

Pre-existing Implementation 2026-04-16 findings #1 (RESOLVED 2026-04-15), #3 and #4 (RESOLVED 2026-04-17 by the Worker.id retype landed in this commit) and #2 (`executor(at index: Int)` raw API at Sharded.swift:83 — unchanged, remains DEFERRED).

---

## Modularization — 2026-04-17

> **Verification (per [SUPER-011])**: Ground rules respected — #1 (files enumerated only); #2 (no rewrites of prior sections); #3 (Experiments excluded); #4 (L1 absolute paths used in narrative); #5 (no prior modularization section exists in this audit.md, so no cross-reference); #6 (no revert-class findings).

### Scope

- **Target**: swift-executors `Package.swift` (session commits added `swift-cpu-primitives` dependency); supplementary review of new L1 file placement within existing `swift-cpu-primitives` and `swift-executor-primitives` targets.
- **Skill**: modularization — [MOD-001], [MOD-002], [MOD-003], [MOD-006], [MOD-015], [MOD-EXCEPT-001]
- **Files**: `swift-foundations/swift-executors/Package.swift`. New L1 sources land in pre-existing target directories (`/Users/coen/Developer/swift-primitives/swift-cpu-primitives/Sources/CPU Primitives/` and `/Users/coen/Developer/swift-primitives/swift-executor-primitives/Sources/Executor Job Priority Primitives/`); the L1 `Package.swift` files for those packages are not enumerated in `## Relevant Files` per the brief and are therefore not audited (ground rule #1).

### Findings

No findings.

### Summary

The new `swift-cpu-primitives` dependency in `swift-foundations/swift-executors/Package.swift` is well-formed:

- The dependency line at :27 (`.package(path: "../../swift-primitives/swift-cpu-primitives")`) and the product line at :39 (`.product(name: "CPU Primitives", package: "swift-cpu-primitives")`) match the only product `swift-cpu-primitives` publishes (verified at `/Users/coen/Developer/swift-primitives/swift-cpu-primitives/Package.swift:14–19`).
- `swift-cpu-primitives` is a single-product L1 package — there is no narrower variant to import per [MOD-015]. `import CPU_Primitives` in `Sources/Executors/Kernel.Thread.Executor.Sharded.swift:11` is the canonical consumer-facing import.
- The dependency is downward (L3 → L1) per the Five-Layer Architecture; no upward or lateral dependency was introduced.
- Per [MOD-006] dependency minimization: the `CPU Primitives` product is genuinely used (`CPU.Cache.Padded<Atomic<Index<Kernel.Thread>>>` at Sharded.swift:46). No surplus dependency added.
- Per [MOD-001] (Core requirement): `swift-executors` publishes a single product (`Executors`). The Core/umbrella discipline applies to multi-product packages — single-product packages are not subject to the Core split. The package remains a leaf-style L3 with one library product, consistent with sibling foundations like `swift-io`'s post-decomposition shape.
- The new file `CPU.Cache.Padded.swift` lives in the existing `CPU Primitives` target directory at L1 — fits the existing target's CPU-cache concept domain ([MOD-DOMAIN]). No new target needed.
- The new `_nextSequence` and `Entry.sequence` modifications stay within the existing `Executor Job Priority Primitives` target.

`// MARK: -` semantic group markers per [MOD-013] are not present in the swift-executors `Package.swift`, but the package has only two declared targets (`Executors` and `Executor Tests`) — well below the 5-target threshold the rule applies above.
