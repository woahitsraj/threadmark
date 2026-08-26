import Foundation
import Testing
@testable import ThreadmarkCore

struct PairingTargetTests {
    @Test func parsesDirectPairingLinkWithFragmentToken() throws {
        let target = try PairingTarget(
            pairingURL: "https://remote.example.test:44342/pair#token=one-time-token"
        )

        #expect(target.credential == "one-time-token")
        #expect(target.httpBaseURL.absoluteString == "https://remote.example.test:44342/")
    }

    @Test func parsesHostedPairingLink() throws {
        let target = try PairingTarget(
            pairingURL: "https://app.t3.codes/pair?host=https%3A%2F%2Fdesktop.example.test%3A44342#token=secret"
        )

        #expect(target.credential == "secret")
        #expect(target.httpBaseURL.absoluteString == "https://desktop.example.test:44342/")
    }

    @Test func acceptsLegacyQueryToken() throws {
        let target = try PairingTarget(
            pairingURL: "wss://remote.example.test/pair?token=legacy"
        )

        #expect(target.credential == "legacy")
        #expect(target.httpBaseURL.absoluteString == "https://remote.example.test/")
    }

    @Test func rejectsMissingToken() {
        #expect(throws: PairingError.missingToken) {
            try PairingTarget(pairingURL: "https://remote.example.test/pair")
        }
    }
}
