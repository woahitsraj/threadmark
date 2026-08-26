public enum MenuBarCountMode: String, Codable, CaseIterable, Sendable {
    case none
    case working
    case done
    case workingAndDone

    public init(includesWorking: Bool, includesDone: Bool) {
        switch (includesWorking, includesDone) {
        case (false, false): self = .none
        case (true, false): self = .working
        case (false, true): self = .done
        case (true, true): self = .workingAndDone
        }
    }

    public var includesWorking: Bool {
        self == .working || self == .workingAndDone
    }

    public var includesDone: Bool {
        self == .done || self == .workingAndDone
    }

    public func count(in activities: [AgentActivity]) -> Int {
        activities.count { activity in
            if activity.needsReview { return includesDone }
            return switch activity.phase {
            case .starting, .running:
                includesWorking
            case .done:
                false
            case .idle, .waitingForApproval, .waitingForInput, .failed:
                false
            }
        }
    }
}
