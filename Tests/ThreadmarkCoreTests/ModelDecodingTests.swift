import Foundation
import Testing
@testable import ThreadmarkCore

struct ModelDecodingTests {
    @Test func decodesEnvironmentCapabilities() throws {
        let descriptor = try JSONDecoder().decode(EnvironmentDescriptor.self, from: Data("""
        {
          "environmentId": "env-1",
          "label": "Mac",
          "serverVersion": "0.0.40",
          "capabilities": {
            "threadAutoSettlement": true,
            "threadSnooze": true,
            "futureCapability": true
          }
        }
        """.utf8))

        #expect(descriptor.capabilities.threadAutoSettlement == true)
        #expect(descriptor.capabilities.threadSnooze == true)
    }

    @Test func olderSavedConnectionsDefaultToNoCapabilities() throws {
        let connection = try JSONDecoder().decode(ConnectionConfiguration.self, from: Data("""
        {
          "baseURL": "https://example.test/",
          "environmentId": "env-1",
          "label": "Mac",
          "grantedScopes": ["orchestration:read"]
        }
        """.utf8))

        #expect(connection.capabilities == EnvironmentCapabilities())
    }
}
