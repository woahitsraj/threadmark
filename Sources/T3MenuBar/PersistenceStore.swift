import Foundation
import T3MenuBarCore

struct PersistenceStore {
    private enum Key {
        static let connection = "connection"
        static let notificationsEnabled = "notificationsEnabled"
        static let menuBarCountMode = "menuBarCountMode"
        static let activityTrackingVersion = "activityTrackingVersion"
        static let fingerprintPrefix = "fingerprints."
        static let armedPrefix = "armed."
        static let unreviewedPrefix = "unreviewed."
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.notificationsEnabled: true])
        if defaults.integer(forKey: Key.activityTrackingVersion) < 2 {
            for key in defaults.dictionaryRepresentation().keys where
                key.hasPrefix(Key.fingerprintPrefix) ||
                key.hasPrefix(Key.armedPrefix) ||
                key.hasPrefix(Key.unreviewedPrefix) {
                defaults.removeObject(forKey: key)
            }
            defaults.set(2, forKey: Key.activityTrackingVersion)
        }
    }

    var connection: ConnectionConfiguration? {
        guard let data = defaults.data(forKey: Key.connection) else { return nil }
        return try? decoder.decode(ConnectionConfiguration.self, from: data)
    }

    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Key.notificationsEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    var menuBarCountMode: MenuBarCountMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.menuBarCountMode) else { return .working }
            return MenuBarCountMode(rawValue: rawValue) ?? .working
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.menuBarCountMode) }
    }

    func save(connection: ConnectionConfiguration) throws {
        defaults.set(try encoder.encode(connection), forKey: Key.connection)
    }

    func clearConnection() {
        defaults.removeObject(forKey: Key.connection)
    }

    func fingerprints(for environmentId: String) -> [String: String] {
        defaults.dictionary(forKey: Key.fingerprintPrefix + environmentId) as? [String: String] ?? [:]
    }

    func save(fingerprints: [String: String], for environmentId: String) {
        defaults.set(fingerprints, forKey: Key.fingerprintPrefix + environmentId)
    }

    func clearFingerprints(for environmentId: String) {
        defaults.removeObject(forKey: Key.fingerprintPrefix + environmentId)
    }

    func armedThreadIds(for environmentId: String) -> Set<String> {
        Set(defaults.stringArray(forKey: Key.armedPrefix + environmentId) ?? [])
    }

    func save(armedThreadIds: Set<String>, for environmentId: String) {
        defaults.set(armedThreadIds.sorted(), forKey: Key.armedPrefix + environmentId)
    }

    func clearArmedThreadIds(for environmentId: String) {
        defaults.removeObject(forKey: Key.armedPrefix + environmentId)
    }

    func unreviewedFingerprints(for environmentId: String) -> Set<String> {
        Set(defaults.stringArray(forKey: Key.unreviewedPrefix + environmentId) ?? [])
    }

    func save(unreviewedFingerprints: Set<String>, for environmentId: String) {
        defaults.set(unreviewedFingerprints.sorted(), forKey: Key.unreviewedPrefix + environmentId)
    }

    func clearUnreviewedFingerprints(for environmentId: String) {
        defaults.removeObject(forKey: Key.unreviewedPrefix + environmentId)
    }
}
