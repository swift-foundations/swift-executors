//
//  Kernel.Thread.Executor.PriorityOverride.swift
//  swift-executors
//
//  Drain-path helper for the M3 (Darwin thread-QoS bump) mechanism
//  per Research/priority-escalation-policy.md. Brackets job execution
//  with pthread_override_qos_class_start_np / _end_np on Darwin so
//  the running job's OS-level thread QoS matches its
//  ExecutorJob.priority, implementing the PIP bound of
//  Sha-Rajkumar-Lehoczky 1990 at the executor layer.
//
//  On non-Darwin platforms this reduces to a direct `runSynchronously`
//  call; the flag is accepted for source compatibility but produces
//  no runtime effect (see priority-escalation-policy.md §Rationale).
//

#if canImport(Darwin)
import Darwin
#endif

extension Kernel.Thread.Executor {

    /// Run a job on the current thread, optionally bracketing its
    /// execution with a Darwin pthread QoS override matching the
    /// job's `priority`.
    ///
    /// - Parameters:
    ///   - job: The job to execute.
    ///   - executor: The unowned-executor identity to report.
    ///   - priorityTracking: If `true` and on Darwin, the current
    ///     thread's QoS is bumped to match `job.priority` for the
    ///     duration of the call, then reverted. If `false` or on
    ///     non-Darwin, the job runs without adjustment.
    internal static func runJob(
        _ job: UnownedJob,
        onSerial executor: UnownedSerialExecutor,
        priorityTracking: Bool
    ) {
        #if canImport(Darwin)
        if priorityTracking, let qos = _qosClass(for: job) {
            let override = unsafe pthread_override_qos_class_start_np(
                pthread_self(), qos, 0
            )
            unsafe job.runSynchronously(on: executor)
            unsafe _ = pthread_override_qos_class_end_np(override)
        } else {
            unsafe job.runSynchronously(on: executor)
        }
        #else
        unsafe job.runSynchronously(on: executor)
        #endif
    }

    /// `UnownedTaskExecutor`-identity variant. See
    /// `runJob(_:onSerial:priorityTracking:)`.
    internal static func runJob(
        _ job: UnownedJob,
        onTask executor: UnownedTaskExecutor,
        priorityTracking: Bool
    ) {
        #if canImport(Darwin)
        if priorityTracking, let qos = _qosClass(for: job) {
            let override = unsafe pthread_override_qos_class_start_np(
                pthread_self(), qos, 0
            )
            unsafe job.runSynchronously(on: executor)
            unsafe _ = pthread_override_qos_class_end_np(override)
        } else {
            unsafe job.runSynchronously(on: executor)
        }
        #else
        unsafe job.runSynchronously(on: executor)
        #endif
    }
}

#if canImport(Darwin)

/// Convert an `UnownedJob`'s `priority` into a `qos_class_t`.
///
/// Returns `nil` when the raw priority is `0` (UNSPECIFIED — no
/// override meaningful) or when the raw value does not match one of
/// the defined `qos_class_t` constants. Accepts only the six Darwin-
/// defined QoS raw values so that stray priority bits do not drive
/// the override to an unmapped class.
internal func _qosClass(for job: UnownedJob) -> qos_class_t? {
    let raw = UInt32(job.priority.rawValue)
    switch raw {
    case QOS_CLASS_USER_INTERACTIVE.rawValue: return QOS_CLASS_USER_INTERACTIVE
    case QOS_CLASS_USER_INITIATED.rawValue:   return QOS_CLASS_USER_INITIATED
    case QOS_CLASS_DEFAULT.rawValue:          return QOS_CLASS_DEFAULT
    case QOS_CLASS_UTILITY.rawValue:          return QOS_CLASS_UTILITY
    case QOS_CLASS_BACKGROUND.rawValue:       return QOS_CLASS_BACKGROUND
    default:                                   return nil
    }
}

#endif
