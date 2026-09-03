import Foundation

public struct PairingTarget: Equatable, Sendable {
    public let credential: String
    public let httpBaseURL: URL

    public init(pairingURL rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pairingURL = URL(string: trimmed), Self.isSupported(pairingURL.scheme) else {
            throw PairingError.invalidURL
        }

        let components = URLComponents(url: pairingURL, resolvingAgainstBaseURL: false)
        let token = Self.value(named: "token", inFragmentOf: components)
            ?? Self.value(named: "token", in: components?.queryItems)
        guard let credential = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !credential.isEmpty else {
            throw PairingError.missingToken
        }

        if let hosted = Self.value(named: "host", in: components?.queryItems) {
            httpBaseURL = try Self.normalizedBaseURL(hosted)
        } else {
            httpBaseURL = try Self.normalizedBaseURL(pairingURL.absoluteString)
        }
        self.credential = credential
    }

    private static func value(named name: String, in items: [URLQueryItem]?) -> String? {
        items?.first(where: { $0.name == name })?.value
    }

    private static func value(named name: String, inFragmentOf components: URLComponents?) -> String? {
        guard let fragment = components?.fragment else { return nil }
        return URLComponents(string: "?\(fragment)")?.queryItems?.first(where: { $0.name == name })?.value
    }

    private static func normalizedBaseURL(_ rawValue: String) throws -> URL {
        let withoutLeadingSlashes = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^/+"#, with: "", options: .regularExpression)
        let includesScheme = withoutLeadingSlashes.range(
            of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#,
            options: .regularExpression
        ) != nil
        let normalized = includesScheme ? withoutLeadingSlashes : "https://\(withoutLeadingSlashes)"
        guard var components = URLComponents(string: normalized), isSupported(components.scheme) else {
            throw PairingError.invalidHost
        }
        if components.scheme == "ws" { components.scheme = "http" }
        if components.scheme == "wss" { components.scheme = "https" }
        if components.scheme == "http",
           let host = components.host,
           !isAllowedInsecureHost(host) {
            throw PairingError.invalidHost
        }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        guard let url = components.url, url.host != nil else { throw PairingError.invalidHost }
        return url
    }

    private static func isSupported(_ scheme: String?) -> Bool {
        ["http", "https", "ws", "wss"].contains(scheme?.lowercased())
    }

    private static func isAllowedInsecureHost(_ host: String) -> Bool {
        let host = host.lowercased()
        let addressHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost"
            || (!host.contains(".") && !host.contains(":"))
            || host.hasSuffix(".local")
            || host.hasSuffix(".ts.net") {
            return true
        }
        if addressHost.contains(":"),
           addressHost == "::1"
            || ["fc", "fd", "fe8", "fe9", "fea", "feb"].contains(where: addressHost.hasPrefix) {
            return true
        }
        let octets = addressHost.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        return octets[0] == 10
            || octets[0] == 127
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 100 && (64...127).contains(octets[1]))
    }
}

public enum PairingError: LocalizedError, Equatable {
    case invalidURL
    case invalidHost
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "That pairing URL is not valid."
        case .invalidHost: "The pairing URL contains an invalid T3 host."
        case .missingToken: "The pairing URL is missing its one-time token."
        }
    }
}
