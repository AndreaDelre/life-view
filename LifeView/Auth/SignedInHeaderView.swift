import GoogleAuth
import SwiftUI

/// Compact account chip rendered in the panel's top header when the
/// user is signed in. Tapping the avatar opens a menu with the
/// disconnect action.
///
/// Replaces the P2 full-screen "signed in" card now that the panel body
/// is occupied by the tasks view.
struct SignedInHeaderView: View {
    let account: Account
    let isWorking: Bool
    let onSignOut: () -> Void

    var body: some View {
        Menu {
            Section {
                Text(account.profile.email)
                if let name = account.profile.displayName, !name.isEmpty {
                    Text(name)
                }
            }
            Button(role: .destructive, action: onSignOut) {
                Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .disabled(isWorking)
        } label: {
            ZStack {
                AccountAvatarView(url: account.profile.avatarURL)
                    .frame(width: 28, height: 28)
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Compte \(account.profile.email)")
    }
}
