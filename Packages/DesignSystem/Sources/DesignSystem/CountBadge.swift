import SwiftUI

/// Small monospaced-digit count chip rendered next to a section title.
///
/// Two visual variants:
///
/// - ``Style/soft`` — the default. Sits on an accent-tinted surface,
///   used next to a section header to communicate "X items in this
///   group". Modeled after Todoist / TickTick section counters.
/// - ``Style/quiet`` — text-only, no background. Used inside denser
///   contexts where a tinted chip would visually compete with the
///   surrounding controls.
///
/// The badge is hidden from VoiceOver by default because the count is
/// already part of the surrounding header's accessibility label (e.g.
/// "Liste perso, 3 tâches"). Callers that need an announced badge
/// should override `accessibilityHidden(false)` and supply a label.
public struct CountBadge: View {
    public enum Style: Sendable {
        case soft
        case quiet
    }

    let count: Int
    let style: Style

    public init(count: Int, style: Style = .soft) {
        self.count = count
        self.style = style
    }

    public var body: some View {
        Text("\(count)")
            .font(Typography.captionEmphasised)
            .monospacedDigit()
            .foregroundStyle(foreground)
            .padding(.vertical, 1)
            .padding(.horizontal, Spacing.xs + 2)
            .background(background)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .soft:
            Capsule(style: .continuous)
                .fill(Palette.surfaceAccentSoft)
        case .quiet:
            Color.clear
        }
    }

    private var foreground: Color {
        switch style {
        case .soft: Palette.textPrimary
        case .quiet: Palette.textSecondary
        }
    }
}

#Preview("Soft") {
    HStack(spacing: Spacing.md) {
        CountBadge(count: 3)
        CountBadge(count: 12)
        CountBadge(count: 199)
    }
    .padding()
}

#Preview("Quiet") {
    HStack(spacing: Spacing.md) {
        CountBadge(count: 3, style: .quiet)
        CountBadge(count: 12, style: .quiet)
    }
    .padding()
}
