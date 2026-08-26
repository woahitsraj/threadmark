import AppKit
import Combine
import Foundation
import OSLog
import ThreadmarkCore

@MainActor
final class AppModel: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case online
        case offline(String)
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var connection: ConnectionConfiguration?
    @Published private(set) var activities: [AgentActivity] = []
    @Published private(set) var lastUpdated: Date?
    @Published var pairingURL = ""
    @Published var errorMessage: String?
    @Published var showsSettings = false
    @Published var notificationsEnabled: Bool
    @Published var menuBarCountMode: MenuBarCountMode
    @Published private(set) var launchesAtLogin: Bool

    private let source: any ActivitySource
    private let keychain = KeychainStore()
    private var persistence: PersistenceStore
    private let notifications = NotificationCoordinator()
    private let launchAtLogin: LaunchAtLoginController
    private let navigator = T3CodeNavigator.shared
    private let logger = Logger(subsystem: "com.rajan.threadmark", category: "lifecycle")
    private let projection = ActivityProjection()
    private var tracker = ActivityTracker()
    private var projectedActivities: [AgentActivity] = []
    private var reviewTracker = DoneReviewTracker()
    private var accessToken: String?
    private var pollingTask: Task<Void, Never>?
    private var hasStarted = false

    init(source: any ActivitySource = T3HTTPActivitySource()) {
        let persistence = PersistenceStore()
        let launchAtLogin = LaunchAtLoginController()
        self.source = source
        self.persistence = persistence
        self.launchAtLogin = launchAtLogin
        notificationsEnabled = persistence.notificationsEnabled
        menuBarCountMode = persistence.menuBarCountMode
        launchesAtLogin = launchAtLogin.isEnabled
    }

    var activeCount: Int {
        activities.filter { [.starting, .running].contains($0.phase) }.count
    }

    var approvalCount: Int {
        activities.filter { $0.phase == .waitingForApproval }.count
    }

    var doneCount: Int {
        activities.filter(\.needsReview).count
    }

    var menuBarCount: Int {
        menuBarCountMode.count(in: activities)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        logger.notice("Starting Threadmark")
        notifications.onThreadOpen = { [weak self] target in
            self?.open(target)
        }
        guard let saved = persistence.connection else {
            logger.notice("No saved T3 connection")
            return
        }
        Task { [weak self] in await self?.restoreConnection(saved) }
    }

    private func restoreConnection(_ saved: ConnectionConfiguration) async {
        do {
            let keychain = keychain
            let storedToken = try await Task.detached {
                try keychain.load(for: saved.environmentId)
            }.value
            guard let token = storedToken else {
                logger.error("Saved T3 connection has no Keychain credential")
                persistence.clearConnection()
                return
            }
            connection = saved
            accessToken = token
            tracker = ActivityTracker(
                fingerprints: persistence.fingerprints(for: saved.environmentId),
                armedThreadIds: persistence.armedThreadIds(for: saved.environmentId)
            )
            reviewTracker = DoneReviewTracker(
                unreviewedFingerprints: persistence.unreviewedFingerprints(for: saved.environmentId)
            )
            logger.notice("Starting background polling")
            startPolling()
        } catch {
            logger.error("Could not load T3 credential: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func connect() async {
        guard !pairingURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Paste a T3 pairing URL first."
            return
        }
        pollingTask?.cancel()
        connectionState = .connecting
        errorMessage = nil
        do {
            let paired = try await source.pair(using: pairingURL)
            if let old = connection, old.environmentId != paired.configuration.environmentId {
                try? keychain.delete(for: old.environmentId)
                persistence.clearFingerprints(for: old.environmentId)
                persistence.clearArmedThreadIds(for: old.environmentId)
                persistence.clearUnreviewedFingerprints(for: old.environmentId)
            }
            try keychain.save(paired.accessToken, for: paired.configuration.environmentId)
            try persistence.save(connection: paired.configuration)
            connection = paired.configuration
            accessToken = paired.accessToken
            pairingURL = ""
            tracker = ActivityTracker()
            reviewTracker = DoneReviewTracker(
                unreviewedFingerprints: persistence.unreviewedFingerprints(
                    for: paired.configuration.environmentId
                )
            )
            process(paired.initialSnapshot)
            connectionState = .online
            if notificationsEnabled { _ = await notifications.requestAuthorization() }
            startPolling()
        } catch {
            connectionState = .disconnected
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        pollingTask?.cancel()
        if let connection {
            try? keychain.delete(for: connection.environmentId)
            persistence.clearFingerprints(for: connection.environmentId)
            persistence.clearArmedThreadIds(for: connection.environmentId)
            persistence.clearUnreviewedFingerprints(for: connection.environmentId)
        }
        persistence.clearConnection()
        connection = nil
        accessToken = nil
        activities = []
        projectedActivities = []
        reviewTracker = DoneReviewTracker()
        connectionState = .disconnected
        showsSettings = false
    }

    func refresh() async {
        await pollOnce()
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        persistence.notificationsEnabled = enabled
        if enabled { Task { _ = await notifications.requestAuthorization() } }
    }

    func setMenuBarCountMode(_ mode: MenuBarCountMode) {
        menuBarCountMode = mode
        persistence.menuBarCountMode = mode
    }

    func setCountsWorking(_ enabled: Bool) {
        setMenuBarCountMode(MenuBarCountMode(
            includesWorking: enabled,
            includesDone: menuBarCountMode.includesDone
        ))
    }

    func setCountsDone(_ enabled: Bool) {
        setMenuBarCountMode(MenuBarCountMode(
            includesWorking: menuBarCountMode.includesWorking,
            includesDone: enabled
        ))
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            launchesAtLogin = launchAtLogin.isEnabled
        } catch {
            launchesAtLogin = launchAtLogin.isEnabled
            errorMessage = "Launch at login requires the packaged app in Applications. \(error.localizedDescription)"
        }
    }

    func open(_ activity: AgentActivity) {
        Task { [weak self] in
            guard let self else { return }
            do {
                errorMessage = nil
                try await navigator.open(
                    deepLink: activity.deepLink,
                    threadTitle: activity.threadTitle
                )
                if activity.needsReview { markReviewed(activity) }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func open(_ target: NotificationThreadTarget) {
        if let activity = projectedActivities.first(where: {
            $0.id == target.threadId && $0.fingerprint == target.fingerprint
        }) {
            open(activity)
            return
        }
        Task { [weak self] in
            do {
                self?.errorMessage = nil
                let deepLink = self?.connection.flatMap {
                    T3CodeNavigator.deepLink(
                        environmentId: $0.environmentId,
                        threadId: target.threadId
                    )
                }
                try await self?.navigator.open(
                    deepLink: deepLink,
                    threadTitle: target.threadTitle
                )
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func pollOnce() async {
        guard let connection, let accessToken else { return }
        do {
            let snapshot = try await source.snapshot(
                configuration: connection,
                accessToken: accessToken
            )
            process(snapshot)
            connectionState = .online
        } catch {
            logger.error("T3 poll failed: \(error.localizedDescription, privacy: .public)")
            connectionState = .offline(error.localizedDescription)
        }
    }

    private func process(_ snapshot: ActivitySnapshot) {
        guard let connection else { return }
        let projected = projection.project(
            snapshot: snapshot.environment,
            environmentId: connection.environmentId,
            changeRequestsByThreadId: snapshot.changeRequestsByThreadId
        )
        let transitions = tracker.observe(projected)
        projectedActivities = projected
        activities = reviewTracker.update(activities: projected, transitions: transitions)
        persistence.save(
            unreviewedFingerprints: reviewTracker.unreviewedFingerprints,
            for: connection.environmentId
        )
        lastUpdated = Date()
        persistence.save(fingerprints: tracker.fingerprints, for: connection.environmentId)
        persistence.save(armedThreadIds: tracker.armedThreadIds, for: connection.environmentId)
        if notificationsEnabled {
            for transition in transitions {
                Task { await notifications.deliver(transition) }
            }
        }
    }

    private func markReviewed(_ activity: AgentActivity) {
        guard let connection else { return }
        reviewTracker.markReviewed(activity.fingerprint)
        persistence.save(
            unreviewedFingerprints: reviewTracker.unreviewedFingerprints,
            for: connection.environmentId
        )
        applyReviewFilter()
    }

    private func applyReviewFilter() {
        activities = reviewTracker.visibleActivities(from: projectedActivities)
    }
}
