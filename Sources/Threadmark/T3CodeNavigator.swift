import AppKit
import ApplicationServices
import Foundation
import ThreadmarkCore

@MainActor
final class T3CodeNavigator {
    static let shared = T3CodeNavigator()

    private let bundleIdentifier = "com.t3tools.t3code"

    static func deepLink(environmentId: String, threadId: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let environment = environmentId.addingPercentEncoding(withAllowedCharacters: allowed)
        let thread = threadId.addingPercentEncoding(withAllowedCharacters: allowed)
        guard let environment, let thread else { return nil }
        return URL(string: "t3code://threads/\(environment)/\(thread)")
    }

    func open(deepLink: URL?, threadTitle: String) async throws {
        if let deepLink { _ = NSWorkspace.shared.open(deepLink) }

        guard accessibilityIsTrusted(prompt: true) else {
            throw NavigationError.accessibilityPermissionRequired
        }
        let application = try await runningApplication()
        application.activate(options: [.activateAllWindows])

        for _ in 0..<8 {
            if pressThread(named: threadTitle, in: application) { return }
            try? await Task.sleep(for: .milliseconds(250))
        }

        if openThreadSearch(in: application) {
            try? await Task.sleep(for: .milliseconds(300))
            if setThreadSearchQuery(threadTitle, in: application) {
                for _ in 0..<8 {
                    if pressThread(named: threadTitle, in: application) { return }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        throw NavigationError.threadNotVisible(threadTitle)
    }

    private func accessibilityIsTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func runningApplication() async throws -> NSRunningApplication {
        if let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first {
            return running
        }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            throw NavigationError.t3CodeNotInstalled
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        ) { _, _ in }

        for _ in 0..<20 {
            if let running = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).first {
                return running
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        throw NavigationError.t3CodeDidNotLaunch
    }

    private func pressThread(named threadTitle: String, in application: NSRunningApplication) -> Bool {
        let root = AXUIElementCreateApplication(application.processIdentifier)
        guard let match = findElement(named: threadTitle, under: root),
              let pressable = pressableAncestor(of: match) else { return false }
        return AXUIElementPerformAction(pressable, kAXPressAction as CFString) == .success
    }

    private func openThreadSearch(in application: NSRunningApplication) -> Bool {
        let root = AXUIElementCreateApplication(application.processIdentifier)
        guard let search = findElement(named: "Search threads", under: root),
              let pressable = pressableAncestor(of: search) else { return false }
        return AXUIElementPerformAction(pressable, kAXPressAction as CFString) == .success
    }

    private func setThreadSearchQuery(
        _ query: String,
        in application: NSRunningApplication
    ) -> Bool {
        let root = AXUIElementCreateApplication(application.processIdentifier)
        guard let searchField = findElement(under: root, where: { element in
            let role: String? = attribute(element, name: kAXRoleAttribute as CFString)
            return role == (kAXTextFieldRole as String) &&
                textValues(of: element).contains(where: {
                    normalized($0).localizedCaseInsensitiveContains("search threads")
                })
        }) else { return false }
        _ = AXUIElementSetAttributeValue(
            searchField,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        return AXUIElementSetAttributeValue(
            searchField,
            kAXValueAttribute as CFString,
            query as CFString
        ) == .success
    }

    private func findElement(named title: String, under root: AXUIElement) -> AXUIElement? {
        return findElement(under: root) { element in
            textValues(of: element).contains(where: {
                ThreadTitleMatcher.matches(candidate: $0, threadTitle: title)
            })
        }
    }

    private func findElement(
        under root: AXUIElement,
        where matches: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        var stack = [root]
        var visited = 0

        while let element = stack.popLast(), visited < 7_000 {
            visited += 1
            if matches(element) { return element }
            stack.append(contentsOf: children(of: element).reversed())
        }
        return nil
    }

    private func pressableAncestor(of element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let candidate = current else { return nil }
            if actionNames(of: candidate).contains(kAXPressAction as String) { return candidate }
            current = attribute(candidate, name: kAXParentAttribute as CFString)
        }
        return nil
    }

    private func textValues(of element: AXUIElement) -> [String] {
        [
            kAXTitleAttribute,
            kAXValueAttribute,
            kAXDescriptionAttribute,
            kAXPlaceholderValueAttribute,
        ].compactMap {
            attribute(element, name: $0 as CFString)
        }
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(element, name: kAXChildrenAttribute as CFString) ?? []
    }

    private func actionNames(of element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success else { return [] }
        return value as? [String] ?? []
    }

    private func attribute<Value>(_ element: AXUIElement, name: CFString) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value as? Value
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

enum NavigationError: LocalizedError {
    case accessibilityPermissionRequired
    case t3CodeNotInstalled
    case t3CodeDidNotLaunch
    case threadNotVisible(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Allow Threadmark in System Settings > Privacy & Security > Accessibility, then click the thread again."
        case .t3CodeNotInstalled:
            "T3 Code is not installed on this Mac."
        case .t3CodeDidNotLaunch:
            "T3 Code did not launch."
        case let .threadNotVisible(title):
            "Could not find \"\(title)\" in the T3 Code sidebar."
        }
    }
}
