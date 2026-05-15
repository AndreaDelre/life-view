import Foundation

/// Abstract refresher used by ``GoogleAccountStore`` so tests can stub the
/// network without standing up a fake server.
public protocol TokenRefreshing: Sendable {
    func refresh(refreshToken: String) async throws -> RefreshedAccessToken
}

/// Subset of a successful refresh response. Google does not return a new
/// refresh token on this flow, so we keep the existing one alongside the new
/// access token (handled by ``GoogleAccountStore``).
public struct RefreshedAccessToken: Sendable, Equatable {
    public let accessToken: String
    public let expiresAt: Date

    public init(accessToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }
}

/// Default refresher: posts to `oauth2.googleapis.com/token` with the
/// `refresh_token` grant. Installed-app clients (type "iOS") use **no
/// client_secret** — the client ID alone is the credential.
public struct GoogleTokenRefresher: TokenRefreshing {
    private let clientID: String
    private let http: HTTPClient
    private let clock: @Sendable () -> Date

    public init(
        clientID: String,
        http: HTTPClient = URLSessionHTTPClient(),
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.clientID = clientID
        self.http = http
        self.clock = clock
    }

    public func refresh(refreshToken: String) async throws -> RefreshedAccessToken {
        var request = URLRequest(url: GoogleOAuthEndpoints.token)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])

        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleOAuthError.http(statusCode: response.statusCode)
        }

        let decoded: RefreshResponseBody
        do {
            decoded = try JSONDecoder().decode(RefreshResponseBody.self, from: data)
        } catch {
            throw GoogleOAuthError.decodingFailed
        }

        let expiresAt = clock().addingTimeInterval(TimeInterval(decoded.expiresIn))
        return RefreshedAccessToken(accessToken: decoded.accessToken, expiresAt: expiresAt)
    }

    // MARK: - Helpers

    private struct RefreshResponseBody: Decodable {
        let accessToken: String
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    private static func formBody(_ parameters: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}
