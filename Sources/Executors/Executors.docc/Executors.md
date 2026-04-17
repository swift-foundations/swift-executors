# ``Executors``

@Metadata {
    @DisplayName("Executors")
    @TitleHeading("Swift Foundations")
}

A toolkit of `SerialExecutor` and `TaskExecutor` compositions for actors
that need explicit control over their execution context.

## Overview

`swift-executors` provides named executor compositions built on the
`swift-executor-primitives` building blocks. Each executor is a complete,
shippable composition for a specific dispatch shape — polling, work
stealing, sharded, cooperative, scheduled, or main-thread.

## Topics

### Polling and Work-Driven

- ``Kernel/Thread/Executor/Polling``

### Thread-Pool Compositions

- ``Kernel/Thread/Executor``
- ``Kernel/Thread/Executor/Stealing``
- ``Kernel/Thread/Executor/Sharded``

### Cooperative and Scheduled

- ``Executor/Cooperative``
- ``Executor/Scheduled``

### Platform

- ``Executor/Main``

### Patterns

- <doc:Synchronous-Handoff-to-Actors>
