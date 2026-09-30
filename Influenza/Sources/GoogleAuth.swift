import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Google OAuth 2.0 for an iOS "installed app": PKCE, no client secret, no SDK.
/// Only the read-only Gmail scope is requested. Refresh token lives in the Keychain.
@MainActor
final class GoogleAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum AuthError: Error { case notConfigured, cancelled, reconnectNeeded, badResponse }

    static let shared = GoogleAuth()
    static let scopes = "openid email https://www.googleapis.com/auth/gmail.readonly"

    private var accessToken: String?
    private var expiry = Date.distantPast
    private var session: ASWebAuthenticationSession?

    var clientID: String { (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? "").trimmingCharacters(in: .whitespaces) }
    var isConfigured: Bool { clientID.hasSuffix(".apps.googleusercontent.com") }
    var isSignedIn: Bool { KeychainStore.read(.googleRefreshToken) != nil }
    /// "1234-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.1234-abc"
    private var redirectScheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    private var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    /// Returns the signed-in email address.
    func signIn() async throws -> String? {
        guard isConfigured else { throw AuthError.notConfigured }
        let verifier = Self.randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "consent"), .init(name: "access_type", value: "offline"),
        ]
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: redirectScheme) { url, error in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: error ?? AuthError.cancelled) }
            }
            s.presentationContextProvider = self
            session = s
            s.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.cancelled
        }
        let json = try await tokenRequest([
            "code": code, "client_id": clientID, "redirect_uri": redirectURI,
            "grant_type": "authorization_code", "code_verifier": verifier,
        ])
        guard let refresh = json["refresh_token"] as? String else { throw AuthError.badResponse }
        KeychainStore.save(refresh, for: .googleRefreshToken)
        store(json)
        let email = (json["id_token"] as? String).flatMap(Self.email(fromIDToken:))
        UserDefaults.standard.set(email, forKey: "googleEmail")
        return email
    }

    func validAccessToken() async throws -> String {
        if let accessToken, expiry > .now.addingTimeInterval(60) { return accessToken }
        guard let refresh = KeychainStore.read(.googleRefreshToken) else { throw AuthError.reconnectNeeded }
        do {
            let json = try await tokenRequest(["refresh_token": refresh, "client_id": clientID, "grant_type": "refresh_token"])
            store(json)
            guard let accessToken else { throw AuthError.badResponse }
            return accessToken
        } catch AuthError.reconnectNeeded {
            // Google "Testing" apps expire refresh tokens after 7 days.
            KeychainStore.delete(.googleRefreshToken)
            throw AuthError.reconnectNeeded
        }
    }

    func signOut() async {
        if let token = KeychainStore.read(.googleRefreshToken) {
            var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke?token=\(token)")!)
            r.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: r)
        }
        KeychainStore.delete(.googleRefreshToken)
        UserDefaults.standard.removeObject(forKey: "googleEmail")
        accessToken = nil
    }

    // MARK: -

    private func store(_ json: [String: Any]) {
        accessToken = json["access_token"] as? String
        expiry = .now.addingTimeInterval((json["expires_in"] as? Double) ?? 3000)
    }

    private func tokenRequest(_ params: [String: String]) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: r)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if json["error"] as? String == "invalid_grant" { throw AuthError.reconnectNeeded }
        guard status == 200 else { throw AuthError.badResponse }
        return json
    }

    private static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count > 1, let data = Data(base64URL: String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
    }

    private static func randomURLSafe(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return Data(bytes).base64URL
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    init?(base64URL: String) {
        var s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}
