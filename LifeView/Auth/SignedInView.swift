import GoogleAuth
import SwiftUI

/// "Connecté" screen — avatar + display name + email + disconnect button.
struct SignedInView: View {
    let account: Account
    let isWorking: Bool
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            AccountAvatarView(url: account.profile.avatarURL)
                .frame(width: 56, height: 56)

            VStack(spacing: 2) {
                if let displayName = account.profile.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(.headline)
                }
                Text(account.profile.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button(role: .destructive, action: onSignOut) {
                HStack(spacing: 6) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    Text("Se déconnecter")
                }
            }
            .controlSize(.regular)
            .disabled(isWorking)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SignedInView(
        account: Account(
            id: AccountID("123"),
            profile: AccountProfile(
                email: "ada@example.com",
                displayName: "Ada Lovelace",
                avatarURL: nil
            )
        ),
        isWorking: false,
        onSignOut: {}
    )
    .padding()
    .frame(width: 380)
}
