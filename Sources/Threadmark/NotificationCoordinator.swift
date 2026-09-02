import AppKit
import ThreadmarkCore
import UserNotifications

private enum ThreadmarkNotificationAction: Sendable {
    case open
    case reply(String)
    case markRead
    case approval(requestId: String, decision: ApprovalDecision)
    case userInput(requestId: String, questionId: String, answer: UserInputAnswer)
    case ignore
}

@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var categories: [String: UNNotificationCategory] = [:]
    var onThreadOpen: ((NotificationThreadTarget) -> Void)?
    var onReply: ((NotificationThreadTarget, String) -> Void)?
    var onApproval: ((NotificationThreadTarget, String, ApprovalDecision) -> Void)?
    var onUserInput: ((NotificationThreadTarget, String, String, UserInputAnswer) -> Void)?
    var onMarkRead: ((NotificationThreadTarget) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func deliver(_ transition: ActivityTransition, interactive: Bool) async {
        let activity = transition.activity
        let content = UNMutableNotificationContent()
        content.title = activity.threadTitle
        content.body = body(for: activity)
        content.sound = .default
        content.userInfo = [
            "threadId": activity.id,
            "threadTitle": activity.threadTitle,
            "fingerprint": activity.fingerprint,
        ]
        if interactive, let category = category(for: activity, content: content) {
            categories[category.identifier] = category
            center.setNotificationCategories(Set(categories.values))
            content.categoryIdentifier = category.identifier
        }
        let request = UNNotificationRequest(
            identifier: activity.fingerprint,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    func removeAllDelivered() {
        center.removeAllDeliveredNotifications()
        categories.removeAll()
        center.setNotificationCategories([])
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
        let action: ThreadmarkNotificationAction
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            action = .open
        case "threadmark.reply":
            action = (response as? UNTextInputNotificationResponse)
                .map { .reply($0.userText) } ?? .ignore
        case "threadmark.mark-read":
            action = .markRead
        case let value where value.hasPrefix("threadmark.approval."):
            if let requestId = userInfo["requestId"] as? String,
               let decision = ApprovalDecision(
                rawValue: String(value.dropFirst("threadmark.approval.".count))
               ) {
                action = .approval(requestId: requestId, decision: decision)
            } else {
                action = .ignore
            }
        case let value where value.hasPrefix("threadmark.input.option."):
            if let requestId = userInfo["requestId"] as? String,
               let questionId = userInfo["questionId"] as? String,
               let labels = userInfo["optionLabels"] as? [String],
               let index = Int(value.dropFirst("threadmark.input.option.".count)),
               labels.indices.contains(index) {
                action = .userInput(
                    requestId: requestId,
                    questionId: questionId,
                    answer: .text(labels[index])
                )
            } else {
                action = .ignore
            }
        case "threadmark.input.custom":
            if let response = response as? UNTextInputNotificationResponse,
               let requestId = userInfo["requestId"] as? String,
               let questionId = userInfo["questionId"] as? String {
                action = .userInput(
                    requestId: requestId,
                    questionId: questionId,
                    answer: .text(response.userText)
                )
            } else {
                action = .ignore
            }
        default:
            action = .ignore
        }
        await MainActor.run {
            switch action {
            case .open:
                self.onThreadOpen?(target)
            case let .reply(text):
                self.onReply?(target, text)
            case .markRead:
                self.onMarkRead?(target)
            case let .approval(requestId, decision):
                self.onApproval?(target, requestId, decision)
            case let .userInput(requestId, questionId, answer):
                self.onUserInput?(target, requestId, questionId, answer)
            case .ignore:
                break
            }
            if case .ignore = action {
                return
            }
            self.categories.removeValue(forKey: "threadmark.\(target.fingerprint)")
            self.center.setNotificationCategories(Set(self.categories.values))
        }
    }

    private func category(
        for activity: AgentActivity,
        content: UNMutableNotificationContent
    ) -> UNNotificationCategory? {
        let identifier = "threadmark.\(activity.fingerprint)"
        switch activity.phase {
        case .done, .failed:
            return UNNotificationCategory(
                identifier: identifier,
                actions: [
                    UNTextInputNotificationAction(
                        identifier: "threadmark.reply",
                        title: "Reply",
                        options: [.authenticationRequired],
                        textInputButtonTitle: "Send",
                        textInputPlaceholder: "Reply to this thread"
                    ),
                    UNNotificationAction(
                        identifier: "threadmark.mark-read",
                        title: "Mark as read",
                        options: []
                    ),
                ],
                intentIdentifiers: []
            )
        case .waitingForApproval:
            guard let approval = activity.interactions.approvals.first else { return nil }
            content.userInfo["requestId"] = approval.requestId
            let actions = approval.availableOptions.prefix(4).map { option in
                var options: UNNotificationActionOptions = [.authenticationRequired]
                if [.decline, .cancel].contains(option.decision) {
                    options.insert(.destructive)
                }
                return UNNotificationAction(
                    identifier: "threadmark.approval.\(option.decision.rawValue)",
                    title: option.label,
                    options: options
                )
            }
            return UNNotificationCategory(
                identifier: identifier,
                actions: actions,
                intentIdentifiers: []
            )
        case .waitingForInput:
            guard let input = activity.interactions.userInputs.first,
                  input.questions.count == 1,
                  let question = input.questions.first else { return nil }
            content.userInfo["requestId"] = input.requestId
            content.userInfo["questionId"] = question.id
            content.userInfo["optionLabels"] = question.options.map(\.label)
            var actions: [UNNotificationAction] = []
            if !question.multiSelect {
                actions.append(contentsOf: question.options.prefix(3).enumerated().map { index, option in
                    UNNotificationAction(
                        identifier: "threadmark.input.option.\(index)",
                        title: option.label,
                        options: [.authenticationRequired]
                    )
                })
            }
            actions.append(UNTextInputNotificationAction(
                identifier: "threadmark.input.custom",
                title: "Other…",
                options: [.authenticationRequired],
                textInputButtonTitle: "Send",
                textInputPlaceholder: question.question
            ))
            return UNNotificationCategory(
                identifier: identifier,
                actions: actions,
                intentIdentifiers: []
            )
        case .idle, .starting, .running:
            return nil
        }
    }

    private func body(for activity: AgentActivity) -> String {
        if let message = activity.latestMessage {
            return message
        }
        if activity.phase == .failed, let detail = activity.detail {
            return detail
        }
        return switch activity.phase {
        case .done: "Ready for review"
        case .failed: "Agent failed"
        case .waitingForApproval: "Approval required"
        case .waitingForInput: "Input required"
        case .idle, .starting, .running: "Agent update"
        }
    }
}

struct NotificationThreadTarget: Sendable {
    let threadId: String
    let threadTitle: String
    let fingerprint: String
}
