import Foundation
import Testing
@testable import AccountSync

@Suite struct PKCETests {
    @Test func challengeMatchesRFCExample() {
        // RFC 7636 附录 B
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierIsURLSafeAndUnique() {
        let a = PKCE.verifier(), b = PKCE.verifier()
        #expect(a != b)
        #expect(a.count == 43)
        #expect(a.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }
}

@Suite struct SyncClientTests {
    @Test func buildsLoginURL() throws {
        let client = SyncClient(baseURL: URL(string: "https://sync.test/api/v1")!)
        let url = client.loginURL(provider: .github, challenge: "abc")
        #expect(url.absoluteString == "https://sync.test/api/v1/auth/github/start?challenge=abc")
    }

    @Test func parsesCallback() {
        #expect(SyncClient.parseCallback(URL(string: "openstats://auth/callback?code=xyz")!) == .success("xyz"))
        #expect(SyncClient.parseCallback(URL(string: "openstats://auth/callback?error=cancelled")!) == .failure(.cancelled))
        #expect(SyncClient.parseCallback(URL(string: "openstats://auth/callback?error=bad")!) == .failure(.server(0, "bad")))
        #expect(SyncClient.parseCallback(URL(string: "https://evil.test/?code=xyz")!) == .failure(.invalidCallback))
    }

    @Test func decodesRemoteSettings() throws {
        struct Doc: Codable, Equatable, Sendable { var refreshSeconds: Int }
        let json = #"{"version":3,"updatedAt":"2026-09-15T08:00:00Z","device":"MacBook","document":{"refreshSeconds":5}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let remote = try decoder.decode(RemoteSettings<Doc>.self, from: Data(json.utf8))
        #expect(remote.version == 3)
        #expect(remote.device == "MacBook")
        #expect(remote.document == Doc(refreshSeconds: 5))
        #expect(remote.updatedAt == Date(timeIntervalSince1970: 1_789_459_200))
    }

    @Test func memoryTokenStoreRoundTrips() throws {
        let store = MemoryTokenStore()
        #expect(store.read() == nil)
        try store.write("t")
        #expect(store.read() == "t")
        store.delete()
        #expect(store.read() == nil)
    }
}
