// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum T3ThreadState: Equatable {
    case working
    case waiting
    case waitingForInput
    case waitingForApproval
    case idle
    case completed
    case failed
    case stopped

    var isActive: Bool {
        switch self {
        case .working, .waiting, .waitingForInput, .waitingForApproval: true
        case .idle, .completed, .failed, .stopped: false
        }
    }
}

struct T3ThreadActivity: Equatable, Identifiable {
    let id: String
    let threadID: String
    let environmentID: String
    let environment: String
    let machine: String?
    let project: String
    let title: String
    let provider: String
    let model: String
    let state: T3ThreadState
    let startedAt: Date?
    let completedAt: Date?
    let updatedAt: Date
    let latestRunID: String?
    let activityRunStartedAt: Date?
    let latestUserAuthoredMessageAt: Date?
    let backgroundTaskCount: Int

    var location: String {
        let environmentLabel = machine.flatMap { $0 == environment ? nil : "\(environment) (\($0))" } ?? environment
        return [project, environmentLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct T3EnvironmentIdentity: Equatable {
    let id: String
    let label: String
    let machine: String?
}

struct T3ShellSnapshot: Decodable {
    let threads: [Thread]
    let archivedThreads: [Thread]
    let projects: [Project]

    struct Project: Decodable {
        let id: String
        let title: String
    }

    struct Thread: Decodable {
        let id: String
        let projectID: String
        let title: String
        let providerInstanceID: String
        let modelSelection: ModelSelection?
        let status: String
        let activityRunStatus: String?
        let activityRunStartedAt: String?
        let latestRunStartedAt: String?
        let latestRunRequestedAt: String?
        let latestRunCompletedAt: String?
        let latestUserAuthoredMessageAt: String?
        let latestRunID: String?
        let activeRunID: String?
        let pendingRuntimeRequest: PendingRuntimeRequest?
        let pendingBackgroundTasks: [BackgroundTask]?
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case id, title, status, modelSelection, updatedAt
            case projectID = "projectId"
            case providerInstanceID = "providerInstanceId"
            case latestRunID = "latestRunId"
            case latestUserAuthoredMessageAt = "latestUserAuthoredMessageAt"
            case activeRunID = "activeRunId"
            case activityRunStatus, activityRunStartedAt, latestRunStartedAt, latestRunRequestedAt
            case latestRunCompletedAt, pendingRuntimeRequest, pendingBackgroundTasks
        }
    }

    struct ModelSelection: Decodable {
        let instanceID: String?
        let provider: String?
        let model: String?

        enum CodingKeys: String, CodingKey {
            case instanceID = "instanceId"
            case provider, model
        }
    }

    struct PendingRuntimeRequest: Decodable {
        let kind: String
    }

    struct BackgroundTask: Decodable {
        let taskID: String
        let kind: String?

        enum CodingKeys: String, CodingKey {
            case taskID = "taskId"
            case kind
        }
    }

    func activities(environment: T3EnvironmentIdentity) -> [T3ThreadActivity] {
        var projectTitles: [String: String] = [:]
        for project in projects where projectTitles[project.id] == nil {
            projectTitles[project.id] = project.title
        }
        return (threads + archivedThreads).compactMap { thread in
            guard let updatedAt = Self.date(thread.updatedAt) else { return nil }
            let pending = thread.pendingRuntimeRequest?.kind.lowercased() ?? ""
            let tasks = thread.pendingBackgroundTasks ?? []
            let state = Self.state(thread, pendingKind: pending, backgroundTasks: tasks)
            let activityStartedAt = thread.activityRunStartedAt.flatMap(Self.date)
            let startedAt = [thread.activityRunStartedAt, thread.latestRunStartedAt,
                             thread.latestRunRequestedAt].compactMap { $0 }.compactMap(Self.date).first
            let provider = thread.modelSelection?.instanceID ?? thread.modelSelection?.provider
                ?? thread.providerInstanceID
            return T3ThreadActivity(
                id: "\(environment.id):\(thread.id)", threadID: thread.id,
                environmentID: environment.id, environment: environment.label,
                machine: environment.machine, project: projectTitles[thread.projectID] ?? "",
                title: thread.title, provider: provider,
                model: thread.modelSelection?.model ?? "", state: state,
                startedAt: startedAt, completedAt: thread.latestRunCompletedAt.flatMap(Self.date),
                updatedAt: updatedAt, latestRunID: thread.latestRunID,
                activityRunStartedAt: activityStartedAt,
                latestUserAuthoredMessageAt: thread.latestUserAuthoredMessageAt.flatMap(Self.date),
                backgroundTaskCount: tasks.count)
        }
    }

    static func state(_ thread: Thread, pendingKind: String, backgroundTasks: [BackgroundTask]) -> T3ThreadState {
        if pendingKind == "user_input" || pendingKind == "user_input_request" {
            return .waitingForInput
        }
        if !pendingKind.isEmpty && pendingKind != "auth_refresh" { return .waitingForApproval }
        let runState = thread.activityRunStatus ?? thread.status
        if runState == "failed" { return .failed }
        if backgroundTasks.contains(where: { $0.kind?.lowercased() != "command" }) { return .working }
        switch runState {
        case "preparing", "queued", "starting", "running": return .working
        case "waiting": return .waiting
        case "failed": return .failed
        case "cancelled", "interrupted", "rolled_back": return .stopped
        case "completed": return .completed
        default:
            if thread.activeRunID != nil { return .working }
            if thread.latestRunCompletedAt != nil { return .completed }
            return .idle
        }
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter.t3Fractional.date(from: value) ?? ISO8601DateFormatter.t3.date(from: value)
    }
}

struct T3ActivityCompletion: Equatable {
    let activity: T3ThreadActivity
    let duration: TimeInterval
}

enum T3ActivityPresentation {
    static func visible(_ activities: [T3ThreadActivity], now: Date = .now) -> [T3ThreadActivity] {
        activities.filter {
            $0.state.isActive || (($0.state == .completed || $0.state == .failed || $0.state == .stopped)
                && now.timeIntervalSince($0.completedAt ?? $0.updatedAt) >= 0
                && now.timeIntervalSince($0.completedAt ?? $0.updatedAt) < 10 * 60)
        }
            .sorted { lhs, rhs in
                let leftPriority = priority(lhs.state)
                let rightPriority = priority(rhs.state)
                return leftPriority != rightPriority ? leftPriority < rightPriority : lhs.updatedAt > rhs.updatedAt
            }
            .prefix(8).map { $0 }
    }

    static func layoutKey(_ activities: [T3ThreadActivity], now: Date = .now) -> [String] {
        visible(activities, now: now).map { "\($0.id):\($0.state)" }
    }

    static func contentHeight(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return 34 + CGFloat(count) * 42 + 8
    }

    private static func priority(_ state: T3ThreadState) -> Int {
        switch state {
        case .waitingForApproval: 0
        case .waitingForInput: 1
        case .working: 2
        case .waiting: 3
        case .failed: 4
        case .completed: 5
        case .stopped: 6
        case .idle: 7
        }
    }
}

struct T3ActivityReducer {
    private(set) var activities: [String: T3ThreadActivity] = [:]
    private var announcedRuns: Set<String> = []
    private var activityStarts: [String: Date] = [:]
    private var hasBaseline = false

    mutating func apply(_ next: [T3ThreadActivity]) -> [T3ActivityCompletion] {
        let previous = activities
        let nextByID = Dictionary(next.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var completed: [T3ActivityCompletion] = []
        var nextStarts: [String: Date] = [:]
        for activity in next {
            let old = previous[activity.id]
            if activity.state.isActive {
                let start: Date?
                if let activityStartedAt = activity.activityRunStartedAt {
                    start = activityStartedAt
                } else if let old, old.state.isActive, Self.continues(old, as: activity) {
                    start = activityStarts[activity.id] ?? old.startedAt ?? activity.startedAt
                } else {
                    start = activity.startedAt
                }
                if let start { nextStarts[activity.id] = start }
            } else if hasBaseline, activity.state == .completed,
                      let old, old.state.isActive,
                      let runID = activity.latestRunID,
                      announcedRuns.insert("\(activity.environmentID):\(activity.threadID):\(runID)").inserted {
                let start = Self.continues(old, as: activity)
                    ? activityStarts[activity.id] ?? old.startedAt ?? activity.startedAt
                    : activity.startedAt
                let duration = start.flatMap { start in
                    activity.completedAt.map { max(0, $0.timeIntervalSince(start)) }
                } ?? 0
                completed.append(T3ActivityCompletion(activity: activity, duration: duration))
            }
        }
        hasBaseline = true
        activityStarts = nextStarts
        activities = nextByID
        return completed
    }

    private static func continues(_ old: T3ThreadActivity, as next: T3ThreadActivity) -> Bool {
        if old.latestRunID == next.latestRunID { return true }
        if old.state == .waitingForApproval || old.state == .waitingForInput { return true }
        guard let oldMessage = old.latestUserAuthoredMessageAt,
              oldMessage == next.latestUserAuthoredMessageAt else { return false }
        return old.backgroundTaskCount > 0 || old.state == .waiting
    }
}

private extension ISO8601DateFormatter {
    static let t3: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let t3Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
