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

    /// Hover background for an interactive cell.
    ///
    /// macOS doesn't expose a public "row hover" colour; the convention
    /// in AppKit is a low-alpha label tint so it works in light & dark
    /// without breaking translucency on top of a `NSVisualEffectView`.
    public static let surfaceHover = Color(nsColor: .labelColor).opacity(0.06)

    /// Selected-row background, defers to the user-chosen accent colour
    /// — same behaviour as a `List` selection or a Finder row.
    public static let surfaceSelected = Color(nsColor: .selectedContentBackgroundColor)

    /// Soft tint used to highlight a warning chip / banner without
    /// hijacking the whole row. Derived from `.systemOrange` so it
    /// follows the system warm-warning hue in both modes.
    public static let surfaceWarning = Color(nsColor: .systemOrange).opacity(0.08)

    // MARK: - Text

    /// Primary readable text — task titles, body copy.
    public static let textPrimary = Color(nsColor: .labelColor)
    /// Secondary text — due dates, helper copy, dimmed labels.
    public static let textSecondary = Color(nsColor: .secondaryLabelColor)
    /// Tertiary text — placeholders, "—" empty markers.
    public static let textTertiary = Color(nsColor: .tertiaryLabelColor)

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
