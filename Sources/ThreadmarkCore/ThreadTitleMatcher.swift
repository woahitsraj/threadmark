import Foundation

public enum ThreadTitleMatcher {
    public static func matches(candidate: String, threadTitle: String) -> Bool {
        let target = normalized(threadTitle)
        return !target.isEmpty && normalized(candidate).localizedCaseInsensitiveContains(target)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
