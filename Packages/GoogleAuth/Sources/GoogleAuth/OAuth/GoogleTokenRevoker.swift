import Foundation

/// Abstract revoker for the disconnect flow. Same testability rationale as
/// ``TokenRefreshing``.
public protocol TokenRevoking: Sendable {
    func revoke(token: String) async throws
}

/// Default revoker: posts to `oauth2.googleapis.com/revoke`. Google accepts
/// either an access or a refresh token; revoking the refresh token also
/// invalidates the linked access token, which is what disconnect needs.
public struct GoogleTokenRevoker: TokenRevoking {
    private let http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    public func revoke(token: String) async throws {
        var request = URLRequest(url: GoogleOAuthEndpoints.revoke)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        let (_, response) = try await http.send(request)
        // Google returns 200 on success and 400 for an already-revoked or
        // unknown token. Treat 400 as a soft success: from the user's POV,
        // the token is no longer valid either way.
        switch response.statusCode {
        case 200..<300, 400:
            return
        default:
            throw GoogleOAuthError.http(statusCode: response.statusCode)
        }
    }
}
