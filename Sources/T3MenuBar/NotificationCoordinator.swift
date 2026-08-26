import AppKit
import T3MenuBarCore
import UserNotifications

@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    var onThreadOpen: ((NotificationThreadTarget) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func deliver(_ transition: ActivityTransition) async {
        let activity = transition.activity
        let content = UNMutableNotificationContent()
        content.title = title(for: activity)
        content.subtitle = activity.threadTitle
        content.body = body(for: activity)
        content.sound = .default
        content.userInfo = [
            "threadId": activity.id,
            "threadTitle": activity.threadTitle,
            "fingerprint": activity.fingerprint,
        ]
        let request = UNNotificationRequest(
            identifier: activity.fingerprint,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let threadId = userInfo["threadId"] as? String,
              let threadTitle = userInfo["threadTitle"] as? String,
              let fingerprint = userInfo["fingerprint"] as? String else { return }
        let target = NotificationThreadTarget(
            threadId: threadId,
            threadTitle: threadTitle,
            fingerprint: fingerprint
        )
        await MainActor.run { self.onThreadOpen?(target) }
    }

    private func title(for activity: AgentActivity) -> String {
        switch activity.phase {
        case .done: "Ready for review"
        case .failed: "Agent failed"
        case .waitingForApproval: "Approval required"
        case .waitingForInput: "Input required"
        case .idle, .starting, .running: "Agent update"
        }
    }

    private func body(for activity: AgentActivity) -> String {
        let project = "Project: \(activity.projectTitle)"
        if activity.phase == .failed, let detail = activity.detail {
            return "\(project)\n\(detail)"
        }
        return project
    }
}

struct NotificationThreadTarget: Sendable {
    let threadId: String
    let threadTitle: String
    let fingerprint: String
}
