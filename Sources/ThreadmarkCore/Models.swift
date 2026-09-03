import Foundation

public struct EnvironmentDescriptor: Decodable, Sendable {
    public let environmentId: String
    public let label: String
    public let serverVersion: String
}

public struct AccessTokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Double
    public let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }
}

public struct EnvironmentSnapshot: Decodable, Sendable {
    public let snapshotSequence: Int
    public let projects: [ProjectShell]
    public let threads: [ThreadShell]
    public let updatedAt: String
}

public struct ProjectShell: Decodable, Sendable {
    public let id: String
    public let title: String
    public let workspaceRoot: String?
}

public struct ThreadShell: Decodable, Sendable {
    public let id: String
    public let projectId: String
    public let title: String
    public let createdAt: String
    public let branch: String?
    public let worktreePath: String?
    public let modelSelection: ModelSelection
    public let runtimeMode: ThreadRuntimeMode
    public let interactionMode: ThreadInteractionMode
    public let latestTurn: LatestTurn?
    public let session: AgentSession?
    public let archivedAt: String?
    public let latestUserMessageAt: String?
    public let updatedAt: String
    public let settledOverride: SettledOverride?
    public let settledAt: String?
    public let hasPendingApprovals: Bool
    public let hasPendingUserInput: Bool
    public let backgroundLiveness: BackgroundLiveness?
    public let planProgress: PlanProgress?
    public let linkedPullRequest: LinkedPullRequest?

    public init(
        id: String,
        projectId: String,
        title: String,
        createdAt: String? = nil,
        branch: String? = nil,
        worktreePath: String? = nil,
        modelSelection: ModelSelection,
        runtimeMode: ThreadRuntimeMode = .fullAccess,
        interactionMode: ThreadInteractionMode = .default,
        latestTurn: LatestTurn?,
        session: AgentSession?,
        archivedAt: String? = nil,
        latestUserMessageAt: String? = nil,
        updatedAt: String,
        settledOverride: SettledOverride? = nil,
        settledAt: String? = nil,
        hasPendingApprovals: Bool = false,
        hasPendingUserInput: Bool = false,
        backgroundLiveness: BackgroundLiveness? = nil,
        planProgress: PlanProgress? = nil,
        linkedPullRequest: LinkedPullRequest? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.createdAt = createdAt ?? updatedAt
        self.branch = branch
        self.worktreePath = worktreePath
        self.modelSelection = modelSelection
        self.runtimeMode = runtimeMode
        self.interactionMode = interactionMode
        self.latestTurn = latestTurn
        self.session = session
        self.archivedAt = archivedAt
        self.latestUserMessageAt = latestUserMessageAt
        self.updatedAt = updatedAt
        self.settledOverride = settledOverride
        self.settledAt = settledAt
        self.hasPendingApprovals = hasPendingApprovals
        self.hasPendingUserInput = hasPendingUserInput
        self.backgroundLiveness = backgroundLiveness
        self.planProgress = planProgress
        self.linkedPullRequest = linkedPullRequest
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, title, createdAt, branch, worktreePath
        case modelSelection, runtimeMode, interactionMode, latestTurn, session, archivedAt
        case latestUserMessageAt, updatedAt
        case settledOverride, settledAt
        case hasPendingApprovals, hasPendingUserInput, backgroundLiveness, planProgress
        case linkedPullRequest
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        projectId = try values.decode(String.self, forKey: .projectId)
        title = try values.decode(String.self, forKey: .title)
        createdAt = try values.decodeIfPresent(String.self, forKey: .createdAt)
            ?? values.decode(String.self, forKey: .updatedAt)
        branch = try values.decodeIfPresent(String.self, forKey: .branch)
        worktreePath = try values.decodeIfPresent(String.self, forKey: .worktreePath)
        modelSelection = try values.decode(ModelSelection.self, forKey: .modelSelection)
        runtimeMode = try values.decodeIfPresent(ThreadRuntimeMode.self, forKey: .runtimeMode) ?? .fullAccess
        interactionMode = try values.decodeIfPresent(ThreadInteractionMode.self, forKey: .interactionMode) ?? .default
        latestTurn = try values.decodeIfPresent(LatestTurn.self, forKey: .latestTurn)
        session = try values.decodeIfPresent(AgentSession.self, forKey: .session)
        archivedAt = try values.decodeIfPresent(String.self, forKey: .archivedAt)
        latestUserMessageAt = try values.decodeIfPresent(String.self, forKey: .latestUserMessageAt)
        updatedAt = try values.decode(String.self, forKey: .updatedAt)
        settledOverride = try values.decodeIfPresent(SettledOverride.self, forKey: .settledOverride)
        settledAt = try values.decodeIfPresent(String.self, forKey: .settledAt)
        hasPendingApprovals = try values.decodeIfPresent(Bool.self, forKey: .hasPendingApprovals) ?? false
        hasPendingUserInput = try values.decodeIfPresent(Bool.self, forKey: .hasPendingUserInput) ?? false
        backgroundLiveness = try values.decodeIfPresent(BackgroundLiveness.self, forKey: .backgroundLiveness)
        planProgress = try values.decodeIfPresent(PlanProgress.self, forKey: .planProgress)
        linkedPullRequest = try values.decodeIfPresent(LinkedPullRequest.self, forKey: .linkedPullRequest)
    }
}

public struct LinkedPullRequest: Decodable, Hashable, Sendable {
    public let projectId: String
    public let repository: String
    public let number: Int
    public let url: String

    public init(projectId: String, repository: String, number: Int, url: String) {
        self.projectId = projectId
        self.repository = repository
        self.number = number
        self.url = url
    }
}

public enum ChangeRequestState: String, Decodable, Sendable {
    case open
    case closed
    case merged
}

public struct ChangeRequestStatus: Decodable, Equatable, Sendable {
    public let state: ChangeRequestState
    public let updatedAt: String?

    public init(state: ChangeRequestState, updatedAt: String? = nil) {
        self.state = state
        self.updatedAt = updatedAt
    }
}

public struct ActivitySnapshot: Sendable {
    public let environment: EnvironmentSnapshot
    public let changeRequestsByThreadId: [String: ChangeRequestStatus]
    public let interactionsByThreadId: [String: PendingThreadInteractions]
    public let latestMessagesByThreadId: [String: String]

    public init(
        environment: EnvironmentSnapshot,
        changeRequestsByThreadId: [String: ChangeRequestStatus] = [:],
        interactionsByThreadId: [String: PendingThreadInteractions] = [:],
        latestMessagesByThreadId: [String: String] = [:]
    ) {
        self.environment = environment
        self.changeRequestsByThreadId = changeRequestsByThreadId
        self.interactionsByThreadId = interactionsByThreadId
        self.latestMessagesByThreadId = latestMessagesByThreadId
    }
}

public enum SettledOverride: String, Decodable, Sendable {
    case settled
    case active
}

public struct ModelSelection: Decodable, Sendable {
    public let model: String

    public init(model: String) {
        self.model = model
    }
}

public enum ThreadRuntimeMode: String, Codable, Sendable {
    case approvalRequired = "approval-required"
    case autoAcceptEdits = "auto-accept-edits"
    case auto
    case fullAccess = "full-access"
}

public enum ThreadInteractionMode: String, Codable, Sendable {
    case `default`
    case plan
}

public struct LatestTurn: Decodable, Sendable {
    public let turnId: String
    public let state: TurnState
    public let assistantMessageId: String?
    public let requestedAt: String?
    public let startedAt: String?
    public let completedAt: String?

    public init(
        turnId: String,
        state: TurnState,
        assistantMessageId: String? = nil,
        requestedAt: String? = nil,
        startedAt: String? = nil,
        completedAt: String? = nil
    ) {
        self.turnId = turnId
        self.state = state
        self.assistantMessageId = assistantMessageId
        self.requestedAt = requestedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public enum TurnState: String, Decodable, Sendable {
    case running
    case interrupted
    case completed
    case error
}

public struct AgentSession: Decodable, Sendable {
    public let status: SessionStatus
    public let providerName: String?
    public let lastError: String?
    public let updatedAt: String

    public init(
        status: SessionStatus,
        providerName: String? = nil,
        lastError: String? = nil,
        updatedAt: String
    ) {
        self.status = status
        self.providerName = providerName
        self.lastError = lastError
        self.updatedAt = updatedAt
    }
}

public enum SessionStatus: String, Decodable, Sendable {
    case idle
    case starting
    case running
    case ready
    case interrupted
    case stopped
    case error
}

public enum BackgroundLiveness: String, Decodable, Sendable {
    case working
    case monitoring
}

public struct PlanProgress: Decodable, Sendable {
    public let step: String
    public let completedSteps: Int
    public let totalSteps: Int
}

public struct ConnectionConfiguration: Codable, Equatable, Sendable {
    public let baseURL: URL
    public let environmentId: String
    public let label: String
    public let grantedScopes: [String]

    public init(
        baseURL: URL,
        environmentId: String,
        label: String,
        grantedScopes: [String] = ["orchestration:read"]
    ) {
        self.baseURL = baseURL
        self.environmentId = environmentId
        self.label = label
        self.grantedScopes = grantedScopes
    }

    public var canOperate: Bool {
        grantedScopes.contains("orchestration:operate")
    }

    enum CodingKeys: String, CodingKey {
        case baseURL, environmentId, label, grantedScopes
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try values.decode(URL.self, forKey: .baseURL)
        environmentId = try values.decode(String.self, forKey: .environmentId)
        label = try values.decode(String.self, forKey: .label)
        grantedScopes = try values.decodeIfPresent([String].self, forKey: .grantedScopes)
            ?? ["orchestration:read"]
    }
}

public struct PairedEnvironment: Sendable {
    public let configuration: ConnectionConfiguration
    public let accessToken: String
    public let initialSnapshot: ActivitySnapshot

    public init(
        configuration: ConnectionConfiguration,
        accessToken: String,
        initialSnapshot: ActivitySnapshot
    ) {
        self.configuration = configuration
        self.accessToken = accessToken
        self.initialSnapshot = initialSnapshot
    }
}
