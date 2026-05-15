import AppKit
import Foundation
// `@preconcurrency` because GoogleSignIn-iOS is an Obj-C SDK whose
// types (`GIDSignInResult`, `GIDGoogleUser`…) aren't annotated
// `Sendable`. Without the attribute, Swift 6 strict concurrency rejects
// the `await GIDSignIn.signIn(...)` call as crossing an actor boundary
// with a non-Sendable result. Local Xcode tolerates it, CI's Xcode 16.2
// doesn't — so we pin the relaxed import here. We never let the SDK
// types escape this file: the return value is the Sendable
// ``SignInResult`` struct.
@preconcurrency import GoogleSignIn

/// Result handed back to ``GoogleAccountStore`` after a successful interactive
/// sign-in.
public struct SignInResult: Sendable {
    public let account: Account
    public let tokens: TokenSet
}

/// Thin wrapper around `GIDSignIn` that:
///
/// 1. configures the SDK with our iOS-type OAuth client,
/// 2. drives the interactive `ASWebAuthenticationSession` flow,
/// 3. extracts a ``SignInResult`` that contains only the data LifeView keeps
///    (user ID, profile, tokens), and
/// 4. clears the SDK's own Keychain item so persistence lives exclusively
///    behind ``GoogleAccountStore``. This avoids two competing stores once
///    P4 introduces multi-account.
///
/// `@MainActor` because `signInWithPresentingWindow:` must be called on the
/// main queue and the completion is documented as main-queue too.
@MainActor
public final class GoogleSignInService {
    private let scopes: [String]

    public init(
        clientID: String,
        scopes: [String] = ["https://www.googleapis.com/auth/tasks"]
    ) {
        self.scopes = scopes
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    /// Runs the OAuth consent flow. The returned tuple is ready to hand off
    /// to ``GoogleAccountStore/saveAccount(_:tokens:)``.
    public func signIn(presenting window: NSWindow) async throws -> SignInResult {
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: window,
                hint: nil,
                additionalScopes: scopes
            )
        } catch {
            throw Self.map(error: error)
        }

        let extracted = try Self.extract(from: result)
        // Drop the SDK-managed Keychain copy: LifeView keeps its own.
        GIDSignIn.sharedInstance.signOut()
        return extracted
    }

    // MARK: - Helpers

    private static func extract(from result: GIDSignInResult) throws -> SignInResult {
        let user = result.user
        guard let userID = user.userID,
              let profile = user.profile,
              let expiration = user.accessToken.expirationDate
        else {
            throw GoogleOAuthError.incompleteResponse
        }
        let refreshToken = user.refreshToken.tokenString
        guard !refreshToken.isEmpty else {
            throw GoogleOAuthError.incompleteResponse
        }

        let accountID = AccountID(userID)
        let accountProfile = AccountProfile(
            email: profile.email,
            displayName: profile.name,
            avatarURL: profile.hasImage ? profile.imageURL(withDimension: 96) : nil
        )
        let tokens = TokenSet(
            accessToken: user.accessToken.tokenString,
            refreshToken: refreshToken,
            accessTokenExpiresAt: expiration
        )
        return SignInResult(
            account: Account(id: accountID, profile: accountProfile),
            tokens: tokens
        )
    }

    /// `GIDSignInErrorCodeCanceled`. The Obj-C `NS_ERROR_ENUM` doesn't bridge
    /// to a Swift enum we can name here, so we pin the documented value from
    /// `GIDSignIn.h` (GoogleSignIn 8.x).
    private static let canceledErrorCode = -5

    private static func map(error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == kGIDSignInErrorDomain,
           nsError.code == Self.canceledErrorCode {
            return GoogleOAuthError.userCancelled
        }
        return error
    }
}
