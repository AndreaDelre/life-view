import Foundation

/// Google OAuth 2.0 endpoints used by the refresh and revocation flows.
///
/// The sign-in flow itself goes through `GoogleSignIn-iOS`, which talks to
/// `accounts.google.com`. Only refresh/revoke are reached directly.
enum GoogleOAuthEndpoints {
    // swiftlint:disable force_unwrapping
    // Hard-coded HTTPS URL literals — `URL(string:)` cannot fail here.
    static let token = URL(string: "https://oauth2.googleapis.com/token")!
    static let revoke = URL(string: "https://oauth2.googleapis.com/revoke")!
    // swiftlint:enable force_unwrapping
}
