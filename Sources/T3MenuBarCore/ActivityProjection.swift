import Foundation

public enum ActivityPhase: String, Codable, Sendable {
    case idle
    case starting
    case running
    case waitingForApproval
    case waitingForInput
    case done
    case failed
}

public struct AgentActivity: Identifiable, Equatable, Sendable {
    public let id: String
    public let environmentId: String
    public let projectTitle: String
    public let threadTitle: String
    public let modelTitle: String
    public let phase: ActivityPhase
    public let detail: String?
    public let planProgress: PlanProgressSummary?
    public let updatedAt: Date
    public let deepLink: URL?
    public let fingerprint: String
    public let needsReview: Bool

    public init(
        id: String,
        environmentId: String,
        projectTitle: String,
        threadTitle: String,
        modelTitle: String,
        phase: ActivityPhase,
        detail: String?,
        planProgress: PlanProgressSummary?,
        updatedAt: Date,
        deepLink: URL?,
        fingerprint: String,
        needsReview: Bool = false
    ) {
        self.id = id
        self.environmentId = environmentId
        self.projectTitle = projectTitle
        self.threadTitle = threadTitle
        self.modelTitle = modelTitle
        self.phase = phase
        self.detail = detail
        self.planProgress = planProgress
        self.updatedAt = updatedAt
        self.deepLink = deepLink
        self.fingerprint = fingerprint
        self.needsReview = needsReview
    }

    public func withNeedsReview(_ needsReview: Bool) -> AgentActivity {
        AgentActivity(
            id: id,
            environmentId: environmentId,
            projectTitle: projectTitle,
            threadTitle: threadTitle,
            modelTitle: modelTitle,
            phase: phase,
            detail: detail,
            planProgress: planProgress,
            updatedAt: updatedAt,
            deepLink: deepLink,
            fingerprint: fingerprint,
            needsReview: needsReview
        )
    }

    public func withPhase(_ phase: ActivityPhase) -> AgentActivity {
        AgentActivity(
            id: id,
            environmentId: environmentId,
            projectTitle: projectTitle,
            threadTitle: threadTitle,
            modelTitle: modelTitle,
            phase: phase,
            detail: detail,
            planProgress: planProgress,
            updatedAt: updatedAt,
            deepLink: deepLink,
            fingerprint: fingerprint,
            needsReview: needsReview
        )
    }
}

public struct PlanProgressSummary: Equatable, Sendable {
    public let step: String
    public let completedSteps: Int
    public let totalSteps: Int
}

public struct ActivityTransition: Equatable, Sendable {
    public let activity: AgentActivity

    public init(activity: AgentActivity) {
        self.activity = activity
    }
}

public struct ActivityProjection: Sendable {
    private let autoSettleAfterDays = 3.0
    private let queuedTurnStartGrace: TimeInterval = 2 * 60

    public init() {}

    public func project(
        snapshot: EnvironmentSnapshot,
        environmentId: String,
        changeRequestsByThreadId: [String: ChangeRequestStatus] = [:],
        now: Date = Date()
    ) -> [AgentActivity] {
        let projects = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.title) })
        return snapshot.threads.compactMap { thread in
            guard !isSettled(
                thread,
                changeRequest: changeRequestsByThreadId[thread.id],
                now: now
            ) else { return nil }
            let phase = phase(for: thread)
            let updatedAt = parseDate(thread.updatedAt) ?? now
            let detail = detail(for: phase, thread: thread)
            let progress = thread.planProgress.map {
                PlanProgressSummary(
                    step: $0.step,
                    completedSteps: $0.completedSteps,
                    totalSteps: $0.totalSteps
                )
            }
            return AgentActivity(
                id: thread.id,
                environmentId: environmentId,
                projectTitle: projects[thread.projectId] ?? "Unknown project",
                threadTitle: thread.title,
                modelTitle: thread.modelSelection.model,
                phase: phase,
                detail: detail,
                planProgress: progress,
                updatedAt: updatedAt,
                deepLink: URL(string: "t3code://threads/\(encode(environmentId))/\(encode(thread.id))"),
                fingerprint: fingerprint(for: phase, thread: thread)
            )
        }
        .sorted(by: sortActivities)
    }

    private func phase(for thread: ThreadShell) -> ActivityPhase {
        if thread.hasPendingApprovals { return .waitingForApproval }
        if thread.hasPendingUserInput { return .waitingForInput }
        if thread.session?.status == .error || thread.latestTurn?.state == .error { return .failed }
        if thread.session?.status == .starting { return .starting }
        if thread.backgroundLiveness != nil { return .running }
        if thread.session?.status == .running || thread.latestTurn?.state == .running { return .running }
        if thread.latestTurn?.state == .completed { return .done }
        if thread.latestTurn?.state == .interrupted, thread.latestTurn?.completedAt != nil { return .done }
        return .idle
    }

    private func isSettled(
        _ thread: ThreadShell,
        changeRequest: ChangeRequestStatus?,
        now: Date
    ) -> Bool {
        if thread.archivedAt != nil { return true }
        if thread.hasPendingApprovals || thread.hasPendingUserInput { return false }
        if thread.backgroundLiveness != nil { return false }
        if let status = thread.session?.status, [.starting, .running].contains(status) {
            return false
        }
        if hasQueuedTurnStart(thread, now: now) {
            let serverAdjudicated = thread.settledOverride == .settled
                && thread.settledAt.flatMap(parseDate) != nil
                && thread.latestUserMessageAt.flatMap(parseDate) != nil
                && parseDate(thread.settledAt!)! >= parseDate(thread.latestUserMessageAt!)!
            if !serverAdjudicated { return false }
        }
        if thread.settledOverride == .settled { return true }
        if thread.settledOverride == .active { return false }

        if changeRequestAutoSettles(changeRequest, thread: thread) { return true }
        if changeRequest?.state == .open { return false }

        guard let lastActivity = threadLastActivityAt(thread) else { return false }
        return lastActivity < now.addingTimeInterval(-autoSettleAfterDays * 24 * 60 * 60)
    }

    private func hasQueuedTurnStart(_ thread: ThreadShell, now: Date) -> Bool {
        guard thread.session?.status != .error,
              let messageAt = thread.latestUserMessageAt.flatMap(parseDate),
              abs(now.timeIntervalSince(messageAt)) <= queuedTurnStartGrace else {
            return false
        }
        guard let turn = thread.latestTurn else { return true }
        return [turn.requestedAt, turn.startedAt, turn.completedAt]
            .allSatisfy { $0.flatMap(parseDate).map { $0 < messageAt } ?? true }
    }

    private func changeRequestAutoSettles(
        _ changeRequest: ChangeRequestStatus?,
        thread: ThreadShell
    ) -> Bool {
        guard let changeRequest,
              changeRequest.state == .closed || changeRequest.state == .merged else {
            return false
        }
        guard let updatedAt = changeRequest.updatedAt.flatMap(parseDate) else { return true }
        return updatedAt >= threadUserActivityAnchorAt(thread)
    }

    private func threadUserActivityAnchorAt(_ thread: ThreadShell) -> Date {
        [thread.createdAt, thread.latestUserMessageAt, thread.latestTurn?.requestedAt]
            .compactMap { $0.flatMap(parseDate) }
            .max() ?? .distantPast
    }

    private func threadLastActivityAt(_ thread: ThreadShell) -> Date? {
        [
            thread.latestUserMessageAt,
            thread.latestTurn?.requestedAt,
            thread.latestTurn?.startedAt,
            thread.latestTurn?.completedAt,
        ].compactMap { $0.flatMap(parseDate) }.max()
    }

    private func detail(for phase: ActivityPhase, thread: ThreadShell) -> String? {
        switch phase {
        case .idle:
            nil
        case .failed:
            thread.session?.lastError
        case .running where thread.backgroundLiveness == .monitoring:
            "Monitoring"
        case .running where thread.backgroundLiveness == .working:
            "Background agents are working"
        case .running:
            thread.session?.providerName.map { "\($0) is active" }
        case .done:
            nil
        default:
            nil
        }
    }

    private func fingerprint(for phase: ActivityPhase, thread: ThreadShell) -> String {
        let turn = thread.latestTurn?.turnId ?? "no-turn"
        let terminalStamp = thread.latestTurn?.completedAt ?? thread.session?.updatedAt ?? thread.updatedAt
        let phaseToken = phase == .done ? "completed" : phase.rawValue
        return "\(thread.id):\(phaseToken):\(turn):\(terminalStamp)"
    }

    private func encode(_ value: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private func parseDate(_ value: String) -> Date? {
        if let date = try? Date(value, strategy: .iso8601) { return date }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return try? Date(value, strategy: fractional)
    }

    private func sortActivities(_ lhs: AgentActivity, _ rhs: AgentActivity) -> Bool {
        let rank: [ActivityPhase: Int] = [
            .waitingForApproval: 0,
            .waitingForInput: 1,
            .failed: 2,
            .running: 3,
            .starting: 4,
            .done: 5,
            .idle: 6,
        ]
        let leftRank = rank[lhs.phase, default: 99]
        let rightRank = rank[rhs.phase, default: 99]
        return leftRank == rightRank ? lhs.updatedAt > rhs.updatedAt : leftRank < rightRank
    }
}

public struct ActivityTracker: Sendable {
    public private(set) var fingerprints: [String: String]
    public private(set) var armedThreadIds: Set<String>
    private var hasBaseline: Bool

    public init(
        fingerprints: [String: String] = [:],
        armedThreadIds: Set<String> = [],
        hasBaseline: Bool? = nil
    ) {
        self.fingerprints = fingerprints
        self.armedThreadIds = armedThreadIds
        self.hasBaseline = hasBaseline ?? !fingerprints.isEmpty
    }

    public mutating func observe(_ activities: [AgentActivity]) -> [ActivityTransition] {
        let current = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0.fingerprint) })
        let currentIds = Set(current.keys)
        let previouslyArmed = armedThreadIds
        var nextArmed = armedThreadIds.intersection(currentIds)
        var transitions: [ActivityTransition] = []

        if hasBaseline {
            for activity in activities {
                if Self.isWorking(activity.phase) {
                    nextArmed.insert(activity.id)
                    continue
                }
                if previouslyArmed.contains(activity.id), [.idle, .done].contains(activity.phase) {
                    transitions.append(ActivityTransition(activity: activity.withPhase(.done)))
                    nextArmed.remove(activity.id)
                    continue
                }
                if activity.phase == .failed { nextArmed.remove(activity.id) }
                if fingerprints[activity.id] != activity.fingerprint,
                   Self.isAttentionNotifiable(activity.phase) {
                    transitions.append(ActivityTransition(activity: activity))
                }
            }
        } else {
            nextArmed = Set(activities.filter { Self.isWorking($0.phase) }.map(\.id))
        }

        fingerprints = current
        armedThreadIds = nextArmed
        hasBaseline = true
        return transitions
    }

    private static func isWorking(_ phase: ActivityPhase) -> Bool {
        phase == .starting || phase == .running
    }

    private static func isAttentionNotifiable(_ phase: ActivityPhase) -> Bool {
        switch phase {
        case .failed, .waitingForApproval, .waitingForInput: true
        case .idle, .starting, .running, .done: false
        }
    }
}
