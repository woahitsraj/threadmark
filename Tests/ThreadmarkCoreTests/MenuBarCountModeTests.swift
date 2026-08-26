import Foundation
import Testing
@testable import ThreadmarkCore

struct MenuBarCountModeTests {
    @Test func countCanIncludeWorkingDoneOrBoth() {
        let activities = [activity(.running), activity(.done), activity(.waitingForInput)]

        #expect(MenuBarCountMode.none.count(in: activities) == 0)
        #expect(MenuBarCountMode.working.count(in: activities) == 1)
        #expect(MenuBarCountMode.done.count(in: activities) == 1)
        #expect(MenuBarCountMode.workingAndDone.count(in: activities) == 2)
    }

    @Test func selectionsMapToCountModes() {
        #expect(MenuBarCountMode(includesWorking: false, includesDone: false) == .none)
        #expect(MenuBarCountMode(includesWorking: true, includesDone: false) == .working)
        #expect(MenuBarCountMode(includesWorking: false, includesDone: true) == .done)
        #expect(MenuBarCountMode(includesWorking: true, includesDone: true) == .workingAndDone)
    }

    @Test func doneCountUsesReviewStateNotIdleState() {
        #expect(MenuBarCountMode.done.count(in: [activity(.idle)]) == 0)
        #expect(MenuBarCountMode.done.count(in: [activity(.idle, needsReview: true)]) == 1)
    }

    private func activity(_ phase: ActivityPhase, needsReview: Bool? = nil) -> AgentActivity {
        AgentActivity(
            id: UUID().uuidString,
            environmentId: "env-1",
            projectTitle: "Project",
            threadTitle: "Thread",
            modelTitle: "Model",
            phase: phase,
            detail: nil,
            planProgress: nil,
            updatedAt: .now,
            deepLink: nil,
            fingerprint: UUID().uuidString,
            needsReview: needsReview ?? (phase == .done)
        )
    }
}
