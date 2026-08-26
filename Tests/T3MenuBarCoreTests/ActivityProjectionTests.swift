import Foundation
import Testing
@testable import T3MenuBarCore

struct ActivityProjectionTests {
    private let projection = ActivityProjection()

    @Test func backgroundWorkSuppressesPrematureCompletion() throws {
        let snapshot = try decodeSnapshot(
            sessionStatus: "ready",
            turnState: "completed",
            backgroundLiveness: "working"
        )

        let activity = try #require(projection.project(
            snapshot: snapshot,
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        ).first)

        #expect(activity.phase == .running)
        #expect(activity.detail == "Background agents are working")
    }

    @Test func notifiesOnlyAfterARealTransition() throws {
        let running = projection.project(
            snapshot: try decodeSnapshot(sessionStatus: "running", turnState: "running"),
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let completed = projection.project(
            snapshot: try decodeSnapshot(sessionStatus: "ready", turnState: "completed"),
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        var tracker = ActivityTracker()

        #expect(tracker.observe(running).isEmpty)
        #expect(tracker.observe(completed).map(\.activity.phase) == [.done])
        #expect(tracker.observe(completed).isEmpty)
    }

    @Test func idleCompletionDoesNotBecomeDone() throws {
        let idle = projection.project(
            snapshot: try decodeSnapshot(sessionStatus: "idle", turnState: nil),
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let completed = projection.project(
            snapshot: try decodeSnapshot(sessionStatus: "ready", turnState: "completed"),
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        var tracker = ActivityTracker()

        #expect(tracker.observe(idle).isEmpty)
        #expect(tracker.observe(completed).isEmpty)
    }

    @Test func workingThenIdleBecomesDone() throws {
        let working = projection.project(
            snapshot: try decodeSnapshot(sessionStatus: "running", turnState: "running"),
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let idle = projection.project(
            snapshot: try decodeSnapshot(sessionStatus: "idle", turnState: nil),
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        var tracker = ActivityTracker()

        #expect(tracker.observe(working).isEmpty)
        #expect(tracker.observe(idle).map(\.activity.phase) == [.done])
    }

    @Test func approvalTakesPriorityOverRunning() throws {
        let snapshot = try decodeSnapshot(
            sessionStatus: "running",
            turnState: "running",
            hasPendingApprovals: true
        )

        let activity = try #require(projection.project(
            snapshot: snapshot,
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        ).first)
        #expect(activity.phase == .waitingForApproval)
    }

    @Test func supportsFractionalT3Timestamps() throws {
        let snapshot = try decodeSnapshot(sessionStatus: "running", turnState: "running")
        let activity = try #require(projection.project(
            snapshot: snapshot,
            environmentId: "env/with slash",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        ).first)

        #expect(activity.updatedAt != Date(timeIntervalSince1970: 1_800_000_000))
        #expect(activity.deepLink?.absoluteString.contains("env%2Fwith%20slash") == true)
    }

    @Test func ignoresSettledThreads() throws {
        let snapshot = try decodeSnapshot(
            sessionStatus: "ready",
            turnState: "completed",
            settledOverride: "settled"
        )

        #expect(projection.project(
            snapshot: snapshot,
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        ).isEmpty)
    }

    @Test func idleUnsettledThreadRemainsVisible() throws {
        let snapshot = try decodeSnapshot(
            sessionStatus: "idle",
            turnState: nil
        )

        let activity = try #require(projection.project(
            snapshot: snapshot,
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        ).first)
        #expect(activity.phase == .idle)
    }

    @Test func finishedTurnIsDoneAndTargetsNativeT3Code() throws {
        let snapshot = try decodeSnapshot(sessionStatus: "ready", turnState: "completed")
        let activity = try #require(projection.project(
            snapshot: snapshot,
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        ).first)

        #expect(activity.phase.rawValue == "done")
        #expect(activity.deepLink?.absoluteString == "t3code://threads/env-1/thread-1")
        #expect(activity.fingerprint.contains(":completed:"))
    }

    @Test func recentlyCompletedUnsettledThreadRemainsVisible() throws {
        let snapshot = try decodeSnapshot(sessionStatus: "ready", turnState: "completed")

        let activity = try #require(projection.project(
            snapshot: snapshot,
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_086_401)
        ).first)
        #expect(activity.phase == .done)
    }

    @Test func inactiveThreadIsAutoSettledAfterThreeDays() throws {
        let snapshot = try decodeSnapshot(sessionStatus: "ready", turnState: "completed")

        #expect(projection.project(
            snapshot: snapshot,
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_259_201)
        ).isEmpty)
    }

    @Test func activeBackgroundWorkIsNeverAutoSettled() throws {
        let snapshot = try decodeSnapshot(
            sessionStatus: "ready",
            turnState: "completed",
            backgroundLiveness: "working"
        )

        let activity = try #require(projection.project(
            snapshot: snapshot,
            environmentId: "env-1",
            now: Date(timeIntervalSince1970: 1_800_259_201)
        ).first)
        #expect(activity.phase == .running)
    }

    @Test func mergedPullRequestSettlesThreadWhenItIsTheLatestUserEvent() throws {
        let snapshot = try decodeSnapshot(
            sessionStatus: "ready",
            turnState: "completed",
            latestUserMessageAt: "2027-01-15T07:59:00Z"
        )

        #expect(projection.project(
            snapshot: snapshot,
            environmentId: "env-1",
            changeRequestsByThreadId: [
                "thread-1": ChangeRequestStatus(
                    state: .merged,
                    updatedAt: "2027-01-15T08:01:00Z"
                ),
            ],
            now: Date(timeIntervalSince1970: 1_800_000_000)
        ).isEmpty)
    }

    @Test func userActivityAfterMergeKeepsThreadUnsettled() throws {
        let snapshot = try decodeSnapshot(
            sessionStatus: "ready",
            turnState: "completed",
            latestUserMessageAt: "2027-01-15T08:02:00Z"
        )

        #expect(projection.project(
            snapshot: snapshot,
            environmentId: "env-1",
            changeRequestsByThreadId: [
                "thread-1": ChangeRequestStatus(
                    state: .merged,
                    updatedAt: "2027-01-15T08:01:00Z"
                ),
            ],
            now: Date(timeIntervalSince1970: 1_800_000_000)
        ).count == 1)
    }

    @Test func openPullRequestBlocksInactivitySettlement() throws {
        let snapshot = try decodeSnapshot(sessionStatus: "ready", turnState: "completed")

        #expect(projection.project(
            snapshot: snapshot,
            environmentId: "env-1",
            changeRequestsByThreadId: [
                "thread-1": ChangeRequestStatus(
                    state: .open,
                    updatedAt: "2027-01-15T08:01:00Z"
                ),
            ],
            now: Date(timeIntervalSince1970: 1_800_259_201)
        ).count == 1)
    }

    @Test func activeSessionBlocksPullRequestSettlement() throws {
        let snapshot = try decodeSnapshot(sessionStatus: "running", turnState: "running")

        #expect(projection.project(
            snapshot: snapshot,
            environmentId: "env-1",
            changeRequestsByThreadId: [
                "thread-1": ChangeRequestStatus(
                    state: .closed,
                    updatedAt: "2027-01-15T08:01:00Z"
                ),
            ],
            now: Date(timeIntervalSince1970: 1_800_000_000)
        ).first?.phase == .running)
    }

    private func decodeSnapshot(
        sessionStatus: String,
        turnState: String?,
        backgroundLiveness: String? = nil,
        hasPendingApprovals: Bool = false,
        settledOverride: String? = nil,
        latestUserMessageAt: String? = nil
    ) throws -> EnvironmentSnapshot {
        let background = backgroundLiveness.map { #", "backgroundLiveness": "\#($0)""# } ?? ""
        let settled = settledOverride.map {
            #", "settledOverride": "\#($0)", "settledAt": "2027-01-15T08:01:00.000Z""#
        } ?? #", "settledOverride": null, "settledAt": null"#
        let latestTurn = turnState.map {
            """
            {
              "turnId": "turn-1",
              "state": "\($0)",
              "completedAt": "2027-01-15T08:00:00Z"
            }
            """
        } ?? "null"
        let latestUserMessage = latestUserMessageAt.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "snapshotSequence": 1,
          "projects": [{"id": "project-1", "title": "T3 Code"}],
          "threads": [{
            "id": "thread-1",
            "projectId": "project-1",
            "title": "Build notifications",
            "createdAt": "2027-01-15T07:00:00Z",
            "modelSelection": {"model": "gpt-5.6"},
            "latestTurn": \(latestTurn),
            "session": {
              "status": "\(sessionStatus)",
              "providerName": "Codex",
              "lastError": null,
              "updatedAt": "2027-01-15T08:00:00.123Z"
            },
            "latestUserMessageAt": \(latestUserMessage),
            "updatedAt": "2027-01-15T08:00:00.123Z",
            "hasPendingApprovals": \(hasPendingApprovals),
            "hasPendingUserInput": false
            \(background)
            \(settled)
          }],
          "updatedAt": "2027-01-15T08:00:00Z"
        }
        """
        return try JSONDecoder().decode(EnvironmentSnapshot.self, from: Data(json.utf8))
    }
}
