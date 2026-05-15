import SwiftUI

/// "Pas de compte" screen — shown when no Google account is persisted.
struct SignedOutView: View {
    let isWorking: Bool
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text("Connecte ton compte Google")
                    .font(.headline)
                Text("LifeView a besoin d’accéder à Google Tasks pour afficher tes listes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onSignIn) {
                HStack(spacing: 8) {
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
        .padding(.horizontal, 8)
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
