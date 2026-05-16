import DesignSystem
import SwiftUI

/// "Pas de compte" screen — shown when no Google account is persisted.
struct SignedOutView: View {
    let isWorking: Bool
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "person.crop.circle.badge.plus")
                // Hero glyph for the sign-in screen — scaled relative to
                // `.largeTitle` so it grows with the user's Dynamic Type
                // setting. The previous fixed 44pt swallowed users who
                // bumped the system text size up.
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.xs) {
                Text("Connecte ton compte Google")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("LifeView a besoin d’accéder à Google Tasks pour afficher tes listes.")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onSignIn) {
                HStack(spacing: Spacing.sm) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "g.circle.fill")
                            .accessibilityHidden(true)
                    }
                    Text("Se connecter à Google")
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .accessibilityLabel(isWorking ? "Connexion en cours" : "Se connecter à Google")
            .accessibilityHint("Lance la procédure d’authentification Google dans le navigateur")
        }
        .padding(.horizontal, Spacing.sm)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Idle") {
    SignedOutView(isWorking: false, onSignIn: {})
        .padding()
        .frame(width: 380)
}

#Preview("Working") {
    SignedOutView(isWorking: true, onSignIn: {})
        .padding()
        .frame(width: 380)
}
