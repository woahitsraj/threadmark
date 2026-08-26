import Foundation
import Security

struct KeychainStore: Sendable {
    private let service = "com.rajan.threadmark"
    private let legacyService = "com.rajan.t3menubar"

    func save(_ token: String, for environmentId: String) throws {
        let key = baseQuery(environmentId: environmentId)
        let data = Data(token.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(key as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }

        var add = key
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func load(for environmentId: String) throws -> String? {
        if let token = try load(for: environmentId, service: service) { return token }
        guard let token = try load(for: environmentId, service: legacyService) else { return nil }
        try save(token, for: environmentId)
        try? delete(for: environmentId, service: legacyService)
        return token
    }

    func delete(for environmentId: String) throws {
        try delete(for: environmentId, service: service)
        try delete(for: environmentId, service: legacyService)
    }

    private func load(for environmentId: String, service: String) throws -> String? {
        var query = baseQuery(environmentId: environmentId, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: status)
        }
        return token
    }

    private func delete(for environmentId: String, service: String) throws {
        let status = SecItemDelete(
            baseQuery(environmentId: environmentId, service: service) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery(
        environmentId: String,
        service: String? = nil
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service ?? self.service,
            kSecAttrAccount as String: environmentId,
        ]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
    }
}
