import Foundation
import Testing
@testable import ThreadmarkCore

struct InteractionProjectionTests {
    @Test func keepsOnlyUnresolvedApprovals() throws {
        let activities = try decodeActivities("""
        [
          {
            "kind": "approval.requested",
            "createdAt": "2026-08-27T10:00:00Z",
            "payload": {
              "requestId": "approval-1",
              "requestKind": "command",
              "detail": "swift test",
              "options": [{"decision": "accept", "label": "Approve"}]
            }
          },
          {
            "kind": "approval.requested",
            "createdAt": "2026-08-27T10:01:00Z",
            "payload": {
              "requestId": "approval-2",
              "requestType": "file_change_approval",
              "detail": "Sources/App.swift"
            }
          },
          {
            "kind": "approval.resolved",
            "createdAt": "2026-08-27T10:02:00Z",
            "payload": {"requestId": "approval-1"}
          }
        ]
        """)

        let pending = ThreadInteractionProjection().project(activities)

        #expect(pending.approvals.map(\.requestId) == ["approval-2"])
        #expect(pending.approvals.first?.requestKind == "file-change")
    }

    @Test func decodesStructuredQuestions() throws {
        let activities = try decodeActivities("""
        [
          {
            "kind": "user-input.requested",
            "createdAt": "2026-08-27T10:00:00Z",
            "payload": {
              "requestId": "input-1",
              "questions": [{
                "id": "release",
                "header": "Release",
                "question": "Which channel?",
                "options": [{"label": "Beta", "description": "Ship to testers"}]
              }]
            }
          }
        ]
        """)

        let pending = ThreadInteractionProjection().project(activities)

        #expect(pending.userInputs.first?.questions.first?.id == "release")
        #expect(pending.userInputs.first?.questions.first?.multiSelect == false)
        #expect(pending.userInputs.first?.questions.first?.options.first?.label == "Beta")
    }

    @Test func selectsLatestAssistantMessage() throws {
        let detail = try JSONDecoder().decode(ThreadDetailSnapshot.self, from: Data("""
        {
          "thread": {
            "messages": [
              {"id": "user-1", "role": "user", "text": "Check this"},
              {"id": "assistant-1", "role": "assistant", "text": "Earlier result"},
              {"id": "assistant-2", "role": "assistant", "text": "  Latest result  "}
            ],
            "activities": []
          }
        }
        """.utf8))

        #expect(detail.thread.latestAssistantMessage(matching: "assistant-2") == "Latest result")
    }

    private func decodeActivities(_ json: String) throws -> [ThreadInteractionActivity] {
        try JSONDecoder().decode([ThreadInteractionActivity].self, from: Data(json.utf8))
    }
}
