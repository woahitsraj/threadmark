import Foundation
import OSLog

public protocol ActivitySource: Sendable {
    func pair(using pairingURL: String) async throws -> PairedEnvironment
    func snapshot(configuration: ConnectionConfiguration, accessToken: String) async throws -> ActivitySnapshot
}

public actor T3HTTPActivitySource: ActivitySource {
    private struct CachedChangeRequest: Sendable {
        let status: ChangeRequestStatus
        let fetchedAt: Date
    }

    private struct CachedVCSStatus: Sendable {
        let status: VCSStatus
        let fetchedAt: Date
    }

    private struct VCSStatus: Decodable, Sendable {
        let refName: String?
        let pr: ChangeRequestStatus?
    }

    private struct WebSocketTicket: Decodable {
        let ticket: String
    }

    private struct PullRequestPayload: Encodable {
        let projectId: String
        let repository: String
        let number: Int
    }

    private struct RPCRequest: Encodable {
        let id: String
        let payload: PullRequestPayload
        let _tag = "Request"
        let tag = "pullRequests.detail"
        let headers: [[String]] = []
    }

    private struct VCSStatusPayload: Encodable {
        let cwd: String
    }

    private struct VCSRPCRequest: Encodable {
        let id: String
        let payload: VCSStatusPayload
        let _tag = "Request"
        let tag = "vcs.refreshStatus"
        let headers: [[String]] = []
    }

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "com.rajan.t3menubar", category: "network")
    private var changeRequestCache: [LinkedPullRequest: CachedChangeRequest] = [:]
    private var vcsStatusCache: [String: CachedVCSStatus] = [:]
    private let changeRequestCacheLifetime: TimeInterval = 15

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func pair(using pairingURL: String) async throws -> PairedEnvironment {
        let target = try PairingTarget(pairingURL: pairingURL)
        let descriptor: EnvironmentDescriptor = try await get(
            url: endpoint("/.well-known/t3/environment", at: target.httpBaseURL),
            bearerToken: nil
        )
        let token = try await exchangeToken(at: target.httpBaseURL, credential: target.credential)
        guard token.tokenType == "Bearer" else { throw T3HTTPError.unsupportedTokenType(token.tokenType) }
        let configuration = ConnectionConfiguration(
            baseURL: target.httpBaseURL,
            environmentId: descriptor.environmentId,
            label: descriptor.label
        )
        let initial = try await snapshot(configuration: configuration, accessToken: token.accessToken)
        return PairedEnvironment(
            configuration: configuration,
            accessToken: token.accessToken,
            initialSnapshot: initial
        )
    }

    public func snapshot(
        configuration: ConnectionConfiguration,
        accessToken: String
    ) async throws -> ActivitySnapshot {
        let environment: EnvironmentSnapshot = try await get(
            url: endpoint("/api/orchestration/shell", at: configuration.baseURL),
            bearerToken: accessToken
        )
        let statuses = await changeRequestStatuses(
            for: environment,
            configuration: configuration,
            accessToken: accessToken
        )
        return ActivitySnapshot(environment: environment, changeRequestsByThreadId: statuses)
    }

    private func changeRequestStatuses(
        for snapshot: EnvironmentSnapshot,
        configuration: ConnectionConfiguration,
        accessToken: String
    ) async -> [String: ChangeRequestStatus] {
        let references = Set(snapshot.threads.compactMap(\.linkedPullRequest))
        let projects = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0) })
        let vcsTargets = snapshot.threads.compactMap { thread -> (String, String)? in
            guard thread.linkedPullRequest == nil,
                  thread.branch != nil,
                  let cwd = thread.worktreePath ?? projects[thread.projectId]?.workspaceRoot else {
                return nil
            }
            return (thread.id, cwd)
        }
        let workingDirectories = Set(vcsTargets.map(\.1))
        let now = Date()
        let stale = references.filter {
            guard let cached = changeRequestCache[$0] else { return true }
            return now.timeIntervalSince(cached.fetchedAt) >= changeRequestCacheLifetime
        }
        if !stale.isEmpty {
            do {
                let fresh = try await fetchChangeRequests(
                    Array(stale),
                    configuration: configuration,
                    accessToken: accessToken
                )
                for (reference, status) in fresh {
                    changeRequestCache[reference] = CachedChangeRequest(
                        status: status,
                        fetchedAt: now
                    )
                }
            } catch {
                logger.error(
                    "Pull-request status refresh failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        let staleDirectories = workingDirectories.filter {
            guard let cached = vcsStatusCache[$0] else { return true }
            return now.timeIntervalSince(cached.fetchedAt) >= changeRequestCacheLifetime
        }
        if !staleDirectories.isEmpty {
            do {
                let fresh = try await fetchVCSStatuses(
                    Array(staleDirectories),
                    configuration: configuration,
                    accessToken: accessToken
                )
                for (cwd, status) in fresh {
                    vcsStatusCache[cwd] = CachedVCSStatus(status: status, fetchedAt: now)
                }
            } catch {
                logger.error(
                    "VCS status refresh failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        changeRequestCache = changeRequestCache.filter { references.contains($0.key) }
        vcsStatusCache = vcsStatusCache.filter { workingDirectories.contains($0.key) }
        return Dictionary(uniqueKeysWithValues: snapshot.threads.compactMap { thread in
            if let reference = thread.linkedPullRequest,
               let status = changeRequestCache[reference]?.status {
                return (thread.id, status)
            }
            guard let branch = thread.branch,
                  let cwd = thread.worktreePath ?? projects[thread.projectId]?.workspaceRoot,
                  let status = vcsStatusCache[cwd]?.status,
                  status.refName == branch,
                  let changeRequest = status.pr else { return nil }
            return (thread.id, changeRequest)
        })
    }

    private func fetchChangeRequests(
        _ references: [LinkedPullRequest],
        configuration: ConnectionConfiguration,
        accessToken: String
    ) async throws -> [LinkedPullRequest: ChangeRequestStatus] {
        let socket = try await rpcSocket(configuration: configuration, accessToken: accessToken)
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        let requests = Dictionary(uniqueKeysWithValues: references.enumerated().map { index, reference in
            (String(index), reference)
        })
        let messages = requests.map { id, reference in
            RPCRequest(
                id: id,
                payload: PullRequestPayload(
                    projectId: reference.projectId,
                    repository: reference.repository,
                    number: reference.number
                )
            )
        }
        let encoded = try JSONEncoder().encode(messages)
        guard let payload = String(data: encoded, encoding: .utf8) else {
            throw T3HTTPError.invalidPayload("Could not encode the T3 RPC request.")
        }
        try await socket.send(.string(payload))

        var pending = Set(requests.keys)
        var result: [LinkedPullRequest: ChangeRequestStatus] = [:]
        while !pending.isEmpty {
            let response = try await receive(from: socket)
            for envelope in try rpcEnvelopes(from: response) {
                guard envelope["_tag"] as? String == "Exit",
                      let requestId = rpcId(envelope["requestId"]),
                      let reference = requests[requestId] else { continue }
                pending.remove(requestId)
                guard let exit = envelope["exit"] as? [String: Any],
                      exit["_tag"] as? String == "Success",
                      let value = exit["value"] else { continue }
                let data = try JSONSerialization.data(withJSONObject: value)
                result[reference] = try decoder.decode(ChangeRequestStatus.self, from: data)
            }
        }
        return result
    }

    private func fetchVCSStatuses(
        _ workingDirectories: [String],
        configuration: ConnectionConfiguration,
        accessToken: String
    ) async throws -> [String: VCSStatus] {
        let socket = try await rpcSocket(configuration: configuration, accessToken: accessToken)
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        let requests = Dictionary(uniqueKeysWithValues: workingDirectories.enumerated().map {
            (String($0.offset), $0.element)
        })
        let messages = requests.map { id, cwd in
            VCSRPCRequest(id: id, payload: VCSStatusPayload(cwd: cwd))
        }
        let encoded = try JSONEncoder().encode(messages)
        guard let payload = String(data: encoded, encoding: .utf8) else {
            throw T3HTTPError.invalidPayload("Could not encode the T3 VCS request.")
        }
        try await socket.send(.string(payload))

        var pending = Set(requests.keys)
        var result: [String: VCSStatus] = [:]
        while !pending.isEmpty {
            let response = try await receive(from: socket)
            for envelope in try rpcEnvelopes(from: response) {
                guard envelope["_tag"] as? String == "Exit",
                      let requestId = rpcId(envelope["requestId"]),
                      let cwd = requests[requestId] else { continue }
                pending.remove(requestId)
                guard let exit = envelope["exit"] as? [String: Any],
                      exit["_tag"] as? String == "Success",
                      let value = exit["value"] else { continue }
                let data = try JSONSerialization.data(withJSONObject: value)
                result[cwd] = try decoder.decode(VCSStatus.self, from: data)
            }
        }
        return result
    }

    private func rpcSocket(
        configuration: ConnectionConfiguration,
        accessToken: String
    ) async throws -> URLSessionWebSocketTask {
        var request = URLRequest(
            url: endpoint("/api/auth/websocket-ticket", at: configuration.baseURL)
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let ticket: WebSocketTicket = try await perform(request)
        let socket = session.webSocketTask(with: try webSocketURL(
            baseURL: configuration.baseURL,
            ticket: ticket.ticket
        ))
        socket.resume()
        return socket
    }

    private func receive(
        from socket: URLSessionWebSocketTask
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await socket.receive() }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                socket.cancel(with: .goingAway, reason: nil)
                throw T3HTTPError.transport("T3 did not answer the pull-request status request.")
            }
            let message = try await group.next()!
            group.cancelAll()
            return message
        }
    }

    private func rpcEnvelopes(
        from message: URLSessionWebSocketTask.Message
    ) throws -> [[String: Any]] {
        let data: Data
        switch message {
        case let .data(value): data = value
        case let .string(value): data = Data(value.utf8)
        @unknown default: throw T3HTTPError.invalidResponse
        }
        let object = try JSONSerialization.jsonObject(with: data)
        if let envelopes = object as? [[String: Any]] { return envelopes }
        if let envelope = object as? [String: Any] { return [envelope] }
        throw T3HTTPError.invalidResponse
    }

    private func rpcId(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func webSocketURL(baseURL: URL, ticket: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw T3HTTPError.invalidResponse
        }
        switch components.scheme {
        case "http": components.scheme = "ws"
        case "https": components.scheme = "wss"
        default: throw T3HTTPError.invalidResponse
        }
        components.path = "/ws"
        components.queryItems = [URLQueryItem(name: "wsTicket", value: ticket)]
        components.fragment = nil
        guard let url = components.url else { throw T3HTTPError.invalidResponse }
        return url
    }

    private func exchangeToken(at baseURL: URL, credential: String) async throws -> AccessTokenResponse {
        var request = URLRequest(url: endpoint("/oauth/token", at: baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody([
            ("grant_type", "urn:ietf:params:oauth:grant-type:token-exchange"),
            ("subject_token", credential),
            ("subject_token_type", "urn:t3:params:oauth:token-type:environment-bootstrap"),
            ("requested_token_type", "urn:ietf:params:oauth:token-type:access_token"),
            ("scope", "orchestration:read"),
            ("client_label", "T3 Menubar"),
            ("client_device_type", "desktop"),
            ("client_os", "macOS"),
        ])
        return try await perform(request)
    }

    private func get<Response: Decodable>(url: URL, bearerToken: String?) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw T3HTTPError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw T3HTTPError.server(status: http.statusCode, message: serverMessage(from: data))
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw T3HTTPError.invalidPayload(error.localizedDescription)
            }
        } catch let error as T3HTTPError {
            throw error
        } catch {
            throw T3HTTPError.transport(error.localizedDescription)
        }
    }

    private func endpoint(_ path: String, at baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    private func formBody(_ items: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func serverMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["message"] as? String ?? object["error"] as? String
    }
}

public enum T3HTTPError: LocalizedError, Equatable {
    case invalidResponse
    case invalidPayload(String)
    case server(status: Int, message: String?)
    case transport(String)
    case unsupportedTokenType(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "T3 returned an invalid response."
        case .invalidPayload:
            "This T3 server returned data the menu-bar app does not recognize."
        case let .server(status, message):
            message ?? "T3 returned HTTP \(status)."
        case let .transport(message):
            "Could not reach T3: \(message)"
        case let .unsupportedTokenType(type):
            "This connection requires unsupported \(type) authentication."
        }
    }
}
