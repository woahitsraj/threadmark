public struct DoneReviewTracker: Sendable {
    public private(set) var unreviewedFingerprints: Set<String>

    public init(unreviewedFingerprints: Set<String> = []) {
        self.unreviewedFingerprints = unreviewedFingerprints
    }

    public mutating func update(
        activities: [AgentActivity],
        transitions: [ActivityTransition]
    ) -> [AgentActivity] {
        let currentFingerprints = Set(activities.map(\.fingerprint))
        unreviewedFingerprints.formIntersection(currentFingerprints)
        for transition in transitions where transition.activity.phase == .done {
            unreviewedFingerprints.insert(transition.activity.fingerprint)
        }
        return visibleActivities(from: activities)
    }

    public mutating func markReviewed(_ fingerprint: String) {
        unreviewedFingerprints.remove(fingerprint)
    }

    public func visibleActivities(from activities: [AgentActivity]) -> [AgentActivity] {
        activities.map { activity in
            activity.withNeedsReview(
                unreviewedFingerprints.contains(activity.fingerprint)
            )
        }
    }
}
