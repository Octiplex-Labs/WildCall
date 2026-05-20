@preconcurrency import BackgroundTasks
import Dependencies
import Foundation
import IssueReporting

/// Schedules and handles the BGAppRefreshTask that drives daily pack sync.
/// iOS decides when to actually run the task — we just declare the earliest
/// acceptable time (~24h from each scheduling).
public struct PackRefreshScheduler: Sendable {
    public static let taskIdentifier = "com.octiplex.wildcall.refresh"

    public var register: @Sendable () -> Void
    public var schedule: @Sendable () -> Void

    public init(
        register: @escaping @Sendable () -> Void,
        schedule: @escaping @Sendable () -> Void
    ) {
        self.register = register
        self.schedule = schedule
    }
}

extension PackRefreshScheduler {
    public static let live = PackRefreshScheduler(
        register: {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: PackRefreshScheduler.taskIdentifier,
                using: nil
            ) { task in
                // Apple guarantees the launch handler is invoked on the main
                // queue, so we can safely hop to MainActor isolation.
                MainActor.assumeIsolated {
                    Self.handleAppRefresh(task)
                }
            }
        },
        schedule: {
            Self.scheduleNext()
        }
    )

    @MainActor
    private static func handleAppRefresh(_ task: BGTask) {
        guard let appRefreshTask = task as? BGAppRefreshTask else {
            task.setTaskCompleted(success: false)
            return
        }

        // Schedule the next occurrence before running so a mid-execution
        // cancellation still leaves a pending request for tomorrow.
        Self.scheduleNext()

        let workTask = Task { @MainActor in
            @Dependency(\.packSyncCoordinator) var coordinator
            do {
                _ = try await coordinator.sync()
                appRefreshTask.setTaskCompleted(success: true)
            } catch {
                reportIssue("BGAppRefreshTask sync failed: \(error)")
                appRefreshTask.setTaskCompleted(success: false)
            }
        }
        appRefreshTask.expirationHandler = {
            workTask.cancel()
        }
    }

    private static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: PackRefreshScheduler.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Submission can fail in the simulator (no BGTask runtime) or if
            // background refresh is disabled. Log and move on.
            reportIssue("BGTaskScheduler.submit failed: \(error)")
        }
    }
}

extension PackRefreshScheduler: DependencyKey {
    public static let liveValue: PackRefreshScheduler = .live
    public static let testValue: PackRefreshScheduler = PackRefreshScheduler(
        register: { unimplemented("PackRefreshScheduler.register") },
        schedule: { unimplemented("PackRefreshScheduler.schedule") }
    )
}

extension DependencyValues {
    public var packRefreshScheduler: PackRefreshScheduler {
        get { self[PackRefreshScheduler.self] }
        set { self[PackRefreshScheduler.self] = newValue }
    }
}
