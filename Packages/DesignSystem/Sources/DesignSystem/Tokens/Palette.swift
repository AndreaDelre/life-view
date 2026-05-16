import AppKit
import SwiftUI

/// Semantic colour tokens.
///
/// Strategy: prefer **system `NSColor`s** (mapped through `Color.init(nsColor:)`)
/// for anything that has a clear macOS equivalent — `.labelColor`,
/// `.secondaryLabelColor`, `.controlBackgroundColor`, etc. These are
/// already adaptive: they pick the right shade in light & dark, follow
/// the user's accent colour where it matters, and stay consistent with
/// every other Cocoa surface on the system (Mail, Reminders, Finder).
///
/// For the few tokens that do **not** have a perfect system match
/// (panel hover/selected rows, accent surfaces with custom alpha), we
/// derive them from system colours with a tweaked alpha so they still
/// re-tint themselves automatically.
///
/// We deliberately do *not* use an Asset Catalog: the package is pure
/// Swift code and a code-defined palette keeps reviews diff-friendly
/// (no XML), adds zero bundle-resource setup, and stays Sendable.
public enum Palette {
    // MARK: - Surfaces

    /// The panel itself is materialised via `NSVisualEffectView` — this
    /// token only covers the *content backdrop* used by inline cards
    /// (toast, error chip, etc.). `.controlBackgroundColor` already
    /// adapts to light & dark.
    public static let surfaceBackground = Color(nsColor: .controlBackgroundColor)

    /// Hover background for an interactive cell. Also used by the help
    /// overlay to chip-out shortcut keys.
    ///
    /// macOS doesn't expose a public "row hover" colour; the convention
    /// in AppKit is a low-alpha label tint so it works in light & dark
    /// without breaking translucency on top of a `NSVisualEffectView`.
    /// Bumped from 0.06 → 0.10 alpha so the shortcut chips in the
    /// help overlay (`HelpOverlayView`) draw a perceptible separation
    /// between the key glyph and the panel background — at 0.06 the
    /// chip was visually merging into the sidebar material in light
    /// mode (failing 3:1 non-text contrast). The hover-row use-case
    /// stays subtle enough at 0.10 to read as a hover rather than a
    /// selection.
    public static let surfaceHover = Color(nsColor: .labelColor).opacity(0.10)

    /// Selected-row background, defers to the user-chosen accent colour
    /// — same behaviour as a `List` selection or a Finder row.
    public static let surfaceSelected = Color(nsColor: .selectedContentBackgroundColor)

    /// Soft tint used to highlight a warning chip / banner without
    /// hijacking the whole row. Derived from `.systemOrange` so it
    /// follows the system warm-warning hue in both modes. Bumped from
    /// 0.08 → 0.18 alpha so the chip is unambiguously a warning
    /// surface and not just a slight wash — the previous tint was
    /// barely visible on the sidebar material and failed the 3:1
    /// non-text-contrast threshold against the panel background.
    public static let surfaceWarning = Color(nsColor: .systemOrange).opacity(0.18)

    // MARK: - Text

    /// Primary readable text — task titles, body copy.
    public static let textPrimary = Color(nsColor: .labelColor)
    /// Secondary text — due dates, helper copy, dimmed labels.
    public static let textSecondary = Color(nsColor: .secondaryLabelColor)
    /// Tertiary text — placeholders, "—" empty markers.
    ///
    /// macOS' native `.tertiaryLabelColor` sits around 26% alpha on
    /// `.labelColor`, which gives a ~3.2:1 contrast on the panel
    /// material — fine for purely decorative dashes, **not** enough
    /// for a glyph the user is meant to read. We promote it to
    /// `.secondaryLabelColor` so any text drawn with this token still
    /// clears the 4.5:1 WCAG AA threshold against the sidebar
    /// material. The tertiary semantic is preserved at call-sites
    /// (lowest of three weights) — only the underlying colour gets
    /// slightly darker.
    public static let textTertiary = Color(nsColor: .secondaryLabelColor)

    // MARK: - Accents & status

    /// Brand / accent colour. We follow the user's macOS accent so the
    /// app feels native — there is intentionally no custom brand hue.
    public static let accent = Color.accentColor
    /// Soft hairline separator. Maps to AppKit's standard separator.
    public static let separator = Color(nsColor: .separatorColor)
    /// Destructive / danger surface (delete, irrecoverable action).
    public static let danger = Color(nsColor: .systemRed)
    /// Success — used by completion-tick affordances when emphasised.
    public static let success = Color(nsColor: .systemGreen)
    /// Warning — used by warning banners + inline icons.
    public static let warning = Color(nsColor: .systemOrange)
}
