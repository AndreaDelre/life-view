import DesignSystem
import SwiftUI

/// Loads the Google avatar URL with a graceful fallback to a system glyph.
struct AccountAvatarView: View {
    let url: URL?

    var body: some View {
        ZStack {
            Circle()
                .fill(.tint.opacity(0.15))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.tint)
            .padding(Spacing.xxs)
    }
}
