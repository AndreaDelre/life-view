import DesignSystem
import SwiftUI

/// "Pas de compte" screen — shown when no Google account is persisted.
struct SignedOutView: View {
    let isWorking: Bool
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "person.crop.circle.badge.plus")
                // 44pt hero glyph — bespoke size for the sign-in screen,
                // sits above the typography scale on purpose.
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: Spacing.xs) {
                Text("Connecte ton compte Google")
                    .font(.headline)
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
                    }
                    Text("Se connecter à Google")
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
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
