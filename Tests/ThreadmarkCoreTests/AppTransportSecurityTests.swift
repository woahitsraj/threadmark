import Foundation
import Testing

struct AppTransportSecurityTests {
    @Test func appAllowsPrivateAndTailscaleHTTPConnections() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: projectRoot.appendingPathComponent("Resources/Info.plist"))
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let transportSecurity = try #require(plist["NSAppTransportSecurity"] as? [String: Any])
        let exceptions = try #require(transportSecurity["NSExceptionDomains"] as? [String: Any])
        let tailscaleAddresses = try #require(exceptions["100.64.0.0/10"] as? [String: Any])
        let tailscaleNames = try #require(exceptions["ts.net"] as? [String: Any])

        #expect(transportSecurity["NSAllowsLocalNetworking"] as? Bool == true)
        #expect(transportSecurity["NSAllowsArbitraryLoads"] as? Bool != true)
        #expect(tailscaleAddresses["NSExceptionAllowsInsecureHTTPLoads"] as? Bool == true)
        #expect(tailscaleNames["NSExceptionAllowsInsecureHTTPLoads"] as? Bool == true)
        #expect(tailscaleNames["NSIncludesSubdomains"] as? Bool == true)
    }
}
