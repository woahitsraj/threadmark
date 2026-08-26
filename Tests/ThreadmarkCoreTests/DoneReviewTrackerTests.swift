import Foundation
import Testing
@testable import ThreadmarkCore

struct DoneReviewTrackerTests {
    @Test func completedThreadsRemainVisibleAfterReview() {
        let done = activity(fingerprint: "turn-1")
        var tracker = DoneReviewTracker()

        #expect(tracker.update(activities: [done], transitions: []).first?.needsReview == false)
        let newlyDone = tracker.update(
            activities: [done],
            transitions: [ActivityTransition(activity: done)]
        )
        #expect(newlyDone.map(\.phase) == [.done])
        #expect(newlyDone.first?.needsReview == true)

        tracker.markReviewed(done.fingerprint)
        #expect(tracker.visibleActivities(from: [done]).first?.needsReview == false)
    }

    private func activity(fingerprint: String) -> AgentActivity {
        AgentActivity(
            id: "thread-1",
            environmentId: "env-1",
            projectTitle: "Project",
            threadTitle: "Thread",
            modelTitle: "Model",
            phase: .done,
            detail: "Ready to review",
            planProgress: nil,
            updatedAt: .now,
            deepLink: URL(string: "t3code://app/threads/env-1/thread-1"),
            fingerprint: fingerprint
        )
    }
}
