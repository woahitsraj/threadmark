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

    @Test func rejectsPublicHTTPHost() {
        #expect(throws: PairingError.invalidHost) {
            try PairingTarget(pairingURL: "http://example.com/pair#token=secret")
        }
        #expect(throws: PairingError.invalidHost) {
            try PairingTarget(pairingURL: "http://fdexample.com/pair#token=secret")
        }
        #expect(throws: PairingError.invalidHost) {
            try PairingTarget(pairingURL: "http://[2001:db8::1]/pair#token=secret")
        }
    }

    @Test func acceptsTailscaleHTTPHosts() throws {
        let address = try PairingTarget(
            pairingURL: "http://100.100.10.20:44342/pair#token=secret"
        )
        let magicDNS = try PairingTarget(
            pairingURL: "http://desktop.example.ts.net:44342/pair#token=secret"
        )
        let ipv6 = try PairingTarget(
            pairingURL: "http://[fd7a:115c:a1e0::1]:44342/pair#token=secret"
        )

        #expect(address.httpBaseURL.absoluteString == "http://100.100.10.20:44342/")
        #expect(magicDNS.httpBaseURL.absoluteString == "http://desktop.example.ts.net:44342/")
        #expect(ipv6.httpBaseURL.absoluteString == "http://[fd7a:115c:a1e0::1]:44342/")
    }

    @Test func rejectsMissingToken() {
        #expect(throws: PairingError.missingToken) {
            try PairingTarget(pairingURL: "https://remote.example.test/pair")
        }
    }
}
