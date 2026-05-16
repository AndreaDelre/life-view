import DesignSystem
import SwiftUI

/// Cheat-sheet overlay listing every panel keyboard shortcut.
///
/// Rendered as a ZStack overlay (rather than `.popover` or `.sheet`)
/// for three reasons:
///
/// - The panel is a borderless `NSPanel`. `.popover` works but anchors
///   to a presenting view and adds an arrow chrome that fights the
///   panel's flat aesthetic.
/// - `.sheet` would push a modal NSWindow on top of the panel and steal
///   focus from the rest of the app, defeating the "lightweight
///   inline help" intent.
/// - An overlay keeps the whole interaction inside the panel's own
///   responder chain, so the `?` and `Esc` cascades stay simple.
///
/// Dismissable: clicking the dimmed background, pressing `?` again, or
/// pressing `Esc` all call `onDismiss`. The Esc handling is owned by
/// the parent because Esc has additional cascade semantics (edit →
/// help → panel close).
struct HelpOverlayView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dimmed scrim — clickable, dismisses on tap. Intentionally
            // very translucent: the panel content stays readable
            // behind so the user can correlate "what did this
            // shortcut just do" with the live tasks view.
            Color.black.opacity(0.18)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .transition(.opacity)

            card
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .animation(.easeInOut(duration: 0.16), value: true)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            Divider()
            ForEach(ShortcutCatalog.sections) { section in
                sectionView(section)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Palette.surfaceBackground)
                .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 6)
        )
        .padding(Spacing.lg)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("Raccourcis clavier")
                .font(Typography.titleMedium)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Palette.textSecondary)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help("Fermer (?)")
            .accessibilityLabel("Fermer l’aide")
        }
    }

    private func sectionView(_ section: ShortcutSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(section.title)
                .font(Typography.captionEmphasised)
                .foregroundStyle(Palette.textSecondary)
                .padding(.bottom, Spacing.xxs)
            ForEach(section.entries) { entry in
                row(entry)
            }
        }
    }

    private func row(_ entry: ShortcutEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(entry.keys)
                .font(Typography.captionEmphasised)
                .foregroundStyle(Palette.textPrimary)
                .padding(.vertical, 2)
                .padding(.horizontal, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Palette.surfaceHover)
                )
                .frame(minWidth: 72, alignment: .leading)
            Text(entry.label)
                .font(Typography.caption)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    HelpOverlayView(onDismiss: {})
        .frame(width: 380, height: 600)
        .background(.white)
}
