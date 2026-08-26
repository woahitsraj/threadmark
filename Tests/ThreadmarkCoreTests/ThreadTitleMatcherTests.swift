import Testing
@testable import ThreadmarkCore

struct ThreadTitleMatcherTests {
    @Test func matchesThreadTitleInsideElectronRowLabel() {
        let row = "glide Snooze thread Settle thread GLIDE-3157: Consolidate personal role pages Worktree: t3code-4e477a09"

        #expect(ThreadTitleMatcher.matches(
            candidate: row,
            threadTitle: "GLIDE-3157: Consolidate personal role pages"
        ))
    }
}
