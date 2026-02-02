import XCTest
import CryptoKit
@testable import OpenClawLib

final class OAuthTests: XCTestCase {

    func testGeneratePKCE() throws {
        let pkce = try AnthropicOAuth.generatePKCE()

        XCTAssertFalse(pkce.verifier.isEmpty)
        XCTAssertFalse(pkce.challenge.isEmpty)

        // Base64URL: only alphanumerics, hyphens, underscores (no +, /, =)
        let base64urlPattern = #"^[A-Za-z0-9_-]+$"#
        XCTAssertNotNil(pkce.verifier.range(of: base64urlPattern, options: .regularExpression),
                        "Verifier should be base64url encoded")
        XCTAssertNotNil(pkce.challenge.range(of: base64urlPattern, options: .regularExpression),
                        "Challenge should be base64url encoded")
    }

    func testPKCEChallengeIsHashOfVerifier() throws {
        let pkce = try AnthropicOAuth.generatePKCE()

        // Recompute: challenge = base64url(SHA256(verifier))
        let hash = SHA256.hash(data: Data(pkce.verifier.utf8))
        let expected = Data(hash).base64URLEncodedString()

        XCTAssertEqual(pkce.challenge, expected)
    }

    func testPKCEUniqueness() throws {
        let pkce1 = try AnthropicOAuth.generatePKCE()
        let pkce2 = try AnthropicOAuth.generatePKCE()

        XCTAssertNotEqual(pkce1.verifier, pkce2.verifier)
        XCTAssertNotEqual(pkce1.challenge, pkce2.challenge)
    }

    func testBuildAuthorizeURL() throws {
        let pkce = try AnthropicOAuth.generatePKCE()
        let url = AnthropicOAuth.buildAuthorizeURL(pkce: pkce)

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let queryItems = components.queryItems ?? []
        let params = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.host, "claude.ai")
        XCTAssertEqual(components.path, "/oauth/authorize")
        XCTAssertEqual(params["client_id"], AnthropicOAuth.clientId)
        XCTAssertEqual(params["response_type"], "code")
        XCTAssertEqual(params["code_challenge"], pkce.challenge)
        XCTAssertEqual(params["code_challenge_method"], "S256")
        XCTAssertEqual(params["state"], pkce.verifier)
        XCTAssertNotNil(params["redirect_uri"])
        XCTAssertNotNil(params["scope"])
    }
}
