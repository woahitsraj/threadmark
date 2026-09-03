import Foundation

public enum ApprovalDecision: String, Codable, Sendable {
    case accept
    case acceptForSession
    case acceptAlways
    case decline
    case cancel
}

public struct ApprovalOption: Codable, Equatable, Sendable {
    public let decision: ApprovalDecision
    public let label: String

    public init(decision: ApprovalDecision, label: String) {
        self.decision = decision
        self.label = label
    }
}

public struct PendingApproval: Equatable, Sendable {
    public let requestId: String
    public let requestKind: String
    public let createdAt: String
    public let detail: String?
    public let appName: String?
    public let options: [ApprovalOption]

    public init(
        requestId: String,
        requestKind: String,
        createdAt: String,
        detail: String? = nil,
        appName: String? = nil,
        options: [ApprovalOption] = []
    ) {
        self.requestId = requestId
        self.requestKind = requestKind
        self.createdAt = createdAt
        self.detail = detail
        self.appName = appName
        self.options = options
    }

    public var availableOptions: [ApprovalOption] {
        if !options.isEmpty { return options }
        return [
            ApprovalOption(decision: .cancel, label: "Cancel"),
            ApprovalOption(decision: .decline, label: "Decline"),
            ApprovalOption(decision: .acceptForSession, label: "Always allow this session"),
            ApprovalOption(decision: .accept, label: "Approve"),
        ]
    }
}

public struct UserInputOption: Codable, Equatable, Sendable {
    public let label: String
    public let description: String

    public init(label: String, description: String) {
        self.label = label
        self.description = description
    }
}

public struct UserInputQuestion: Codable, Equatable, Sendable {
    public let id: String
    public let header: String
    public let question: String
    public let options: [UserInputOption]
    public let multiSelect: Bool

    public init(
        id: String,
        header: String,
        question: String,
        options: [UserInputOption],
        multiSelect: Bool = false
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.multiSelect = multiSelect
    }

    enum CodingKeys: String, CodingKey {
        case id, header, question, options, multiSelect
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        header = try values.decode(String.self, forKey: .header)
        question = try values.decode(String.self, forKey: .question)
        options = try values.decode([UserInputOption].self, forKey: .options)
        multiSelect = try values.decodeIfPresent(Bool.self, forKey: .multiSelect) ?? false
    }
}

public struct PendingUserInput: Equatable, Sendable {
    public let requestId: String
    public let createdAt: String
    public let questions: [UserInputQuestion]

    public init(requestId: String, createdAt: String, questions: [UserInputQuestion]) {
        self.requestId = requestId
        self.createdAt = createdAt
        self.questions = questions
    }
}

public enum UserInputAnswer: Equatable, Sendable {
    case text(String)
    case choices([String])
}

public struct PendingThreadInteractions: Equatable, Sendable {
    public let approvals: [PendingApproval]
    public let userInputs: [PendingUserInput]

    public init(approvals: [PendingApproval] = [], userInputs: [PendingUserInput] = []) {
        self.approvals = approvals
        self.userInputs = userInputs
    }
}

struct ThreadDetailSnapshot: Decodable {
    let thread: ThreadDetail
}

struct ThreadDetail: Decodable {
    let messages: [ThreadMessage]
    let activities: [ThreadInteractionActivity]

    enum CodingKeys: String, CodingKey {
        case messages, activities
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        messages = try values.decodeIfPresent([ThreadMessage].self, forKey: .messages) ?? []
        activities = try values.decodeIfPresent(
            [ThreadInteractionActivity].self,
            forKey: .activities
        ) ?? []
    }

    func latestAssistantMessage(matching messageId: String?) -> String? {
        let message = messageId.flatMap { id in
            messages.last { $0.id == id && $0.role == "assistant" }
        }
            ?? messages.last { $0.role == "assistant" }
        let text = message?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

struct ThreadMessage: Decodable {
    let id: String
    let role: String
    let text: String
}

struct ThreadInteractionActivity: Decodable {
    let kind: String
    let payload: ThreadInteractionPayload?
    let createdAt: String
}

struct ThreadInteractionPayload: Decodable {
    let requestId: String?
    let requestKind: String?
    let requestType: String?
    let detail: String?
    let appName: String?
    let options: [ApprovalOption]?
    let questions: [UserInputQuestion]?
}

struct ThreadInteractionProjection: Sendable {
    func project(_ activities: [ThreadInteractionActivity]) -> PendingThreadInteractions {
        var approvals: [String: PendingApproval] = [:]
        var userInputs: [String: PendingUserInput] = [:]

        for activity in activities {
            guard let requestId = activity.payload?.requestId else { continue }
            switch activity.kind {
            case "approval.requested":
                guard let requestKind = requestKind(for: activity.payload) else { continue }
                approvals[requestId] = PendingApproval(
                    requestId: requestId,
                    requestKind: requestKind,
                    createdAt: activity.createdAt,
                    detail: activity.payload?.detail,
                    appName: activity.payload?.appName,
                    options: activity.payload?.options ?? []
                )
            case "approval.resolved":
                approvals.removeValue(forKey: requestId)
            case "provider.approval.respond.failed" where isStale(activity.payload?.detail):
                approvals.removeValue(forKey: requestId)
            case "user-input.requested":
                guard let questions = activity.payload?.questions, !questions.isEmpty else { continue }
                userInputs[requestId] = PendingUserInput(
                    requestId: requestId,
                    createdAt: activity.createdAt,
                    questions: questions
                )
            case "user-input.resolved":
                userInputs.removeValue(forKey: requestId)
            case "provider.user-input.respond.failed" where isStale(activity.payload?.detail):
                userInputs.removeValue(forKey: requestId)
            default:
                continue
            }
        }

        return PendingThreadInteractions(
            approvals: approvals.values.sorted { $0.createdAt < $1.createdAt },
            userInputs: userInputs.values.sorted { $0.createdAt < $1.createdAt }
        )
    }

    private func requestKind(for payload: ThreadInteractionPayload?) -> String? {
        if let requestKind = payload?.requestKind { return requestKind }
        switch payload?.requestType {
        case "command_execution_approval", "exec_command_approval", "dynamic_tool_call":
            return "command"
        case "file_read_approval":
            return "file-read"
        case "file_change_approval", "apply_patch_approval":
            return "file-change"
        case "mcp_elicitation_approval":
            return "mcp-elicitation"
        default:
            return nil
        }
    }

    private func isStale(_ detail: String?) -> Bool {
        guard let detail = detail?.lowercased() else { return false }
        return detail.contains("stale pending approval request")
            || detail.contains("stale pending user-input request")
    }
}
