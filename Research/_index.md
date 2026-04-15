# swift-executors Research Index

| Document | Topic | Date | Status |
|----------|-------|------|--------|
| [composable-executor-abstractions.md](composable-executor-abstractions.md) | Targeted analysis of how `IO.Event.Loop` / `IO.Completion.Loop` compose with `swift-executors` instead of hand-rolling `SerialExecutor` conformances. Recommends Design 1: a held `Polling.Executor` primitive. | 2026-04-15 | RECOMMENDATION (superseded in scope by `executor-package-design.md`; findings preserved as the Design-1 origin) |
| [executor-package-design.md](executor-package-design.md) | Complete-toolkit taxonomy: `swift-executor-primitives` (L1) + seven named compositions in `swift-executors` (L3). Validates V1–V8; post-supervision decisions recorded. | 2026-04-15 | DECISION |
