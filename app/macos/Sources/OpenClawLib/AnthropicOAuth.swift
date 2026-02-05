import Foundation
import CryptoKit

// MARK: - Base64URL Encoding

extension Data {
    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Anthropic OAuth (PKCE)

public enum AnthropicOAuth {
    public static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let authorizeURL = URL(string: "https://claude.ai/oauth/authorize")!
    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!

    // Standard redirect URI (requires manual code copy)
    private static let webRedirectURI = "https://console.anthropic.com/oauth/code/callback"

    // Custom URL scheme for automatic callback (requires Anthropic to accept it)
    public static let customRedirectURI = "openclaw://oauth/callback"

    // Use web redirect by default until we verify Anthropic accepts custom schemes
    private static var redirectURI: String { webRedirectURI }

    private static let scopes = "org:create_api_key user:profile user:inference"

    public struct PKCE {
        public let verifier: String
        public let challenge: String
    }

    public static func generatePKCE() throws -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        let verifier = Data(bytes).base64URLEncodedString()
        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(hash).base64URLEncodedString()
        return PKCE(verifier: verifier, challenge: challenge)
    }

    public static func buildAuthorizeURL(pkce: PKCE) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.verifier),
        ]
        return components.url!
    }

    public static func refreshAccessToken(refreshToken: String) async throws -> OAuthCredentials {
        let payload: [String: Any] = [
            "grant_type": "refresh_token",
            "client_id": clientId,
            "refresh_token": refreshToken,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "<error>"
            throw NSError(domain: "AnthropicOAuth", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: "Token refresh failed: \(text)"])
        }

        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = decoded?["access_token"] as? String,
              let expiresIn = decoded?["expires_in"] as? Double else {
            throw NSError(domain: "AnthropicOAuth", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected refresh response"])
        }

        let newRefresh = decoded?["refresh_token"] as? String ?? refreshToken
        let expiresAtMs = Int64(Date().timeIntervalSince1970 * 1000) + Int64(expiresIn * 1000) - Int64(5 * 60 * 1000)
        return OAuthCredentials(type: "oauth", refresh: newRefresh, access: access, expires: expiresAtMs)
    }

    public static func exchangeCode(code: String, verifier: String) async throws -> OAuthCredentials {
        let payload: [String: Any] = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": code,
            "state": verifier,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "<error>"
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[OpenClaw] Token exchange failed (HTTP \(status)): \(text)")
            throw NSError(domain: "AnthropicOAuth", code: status,
                          userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(text)"])
        }

        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = decoded?["access_token"] as? String,
              let refresh = decoded?["refresh_token"] as? String,
              let expiresIn = decoded?["expires_in"] as? Double else {
            throw NSError(domain: "AnthropicOAuth", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected token response"])
        }

        let expiresAtMs = Int64(Date().timeIntervalSince1970 * 1000) + Int64(expiresIn * 1000) - Int64(5 * 60 * 1000)
        return OAuthCredentials(type: "oauth", refresh: refresh, access: access, expires: expiresAtMs)
    }
}

public struct OAuthCredentials {
    public let type: String
    public let refresh: String
    public let access: String
    public let expires: Int64
}
