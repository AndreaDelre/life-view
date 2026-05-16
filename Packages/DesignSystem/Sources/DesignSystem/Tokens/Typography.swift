import SwiftUI

/// Named typography tokens layered on top of SwiftUI's built-in
/// dynamic-type styles. Using the system styles (`.title2`, `.body`,
/// `.caption`, …) keeps Dynamic Type and accessibility-text-size
/// scaling working out of the box — we just give them semantic names
/// so the call-sites read "panel title" instead of "title2 weight
/// semibold".
public enum Typography {
    // MARK: - Titles

    /// 22pt-ish title — used by the panel header.
    public static let titleLarge = Font.title2.weight(.semibold)
    /// 17pt-ish subtitle — used by section headers (e.g. "Tous les
    /// comptes").
    public static let titleMedium = Font.subheadline.weight(.semibold)
    /// 15pt callout, semibold — used for the per-account header in
    /// aggregated mode.
    public static let titleSmall = Font.callout.weight(.semibold)

    // MARK: - Body

    /// Default body type. Used for task titles and most static text.
    public static let body = Font.body
    /// Body, lighter weight — kept for symmetry; falls back to plain
    /// body so we can refine later without touching call-sites.
    public static let bodySecondary = Font.body
    /// Callout for inline labels (e.g. SignedOut message). Slightly
    /// smaller than body, still very readable.
    public static let callout = Font.callout

    // MARK: - Auxiliary

    /// Subheadline used for in-list group labels (e.g. list title in
    /// aggregated mode).
    public static let subheadline = Font.subheadline.weight(.medium)
    /// Caption — used for due dates, micro-labels, error banner text.
    public static let caption = Font.caption
    /// Caption with emphasis — kept distinct so emphasised captions
    /// can shift weight later without touching every call-site.
    public static let captionEmphasised = Font.caption.weight(.semibold)
}
