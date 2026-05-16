import CoreGraphics

/// 4-point spacing scale used by every padding / stack in the app.
///
/// All values are powers/multiples of 4 so vertical rhythm stays
/// predictable when sub-views compose. Use the named tokens rather
/// than hard-coding magic numbers in views.
public enum Spacing {
    /// 2pt — sub-grid step. Reserved for micro-pairings like a title
    /// stacked on its due-date caption where the 4pt step would
    /// visually disconnect the two.
    public static let xxs: CGFloat = 2
    /// 4pt — tight gap, used for "barely separated" sibling glyphs
    /// (e.g. chevron next to label, leading list indent).
    public static let xs: CGFloat = 4
    /// 8pt — default inter-element gap inside a row.
    public static let sm: CGFloat = 8
    /// 12pt — comfortable gap between blocks of a view.
    public static let md: CGFloat = 12
    /// 16pt — section gap inside the aggregated tasks list.
    public static let lg: CGFloat = 16
    /// 24pt — large vertical separation between unrelated regions.
    public static let xl: CGFloat = 24
    /// 32pt — top-level panel padding for empty states.
    public static let xxl: CGFloat = 32
}

/// Square sizes for circular / square affordances that aren't on the
/// 4pt grid by themselves (avatars, refresh button hit-target). Kept
/// separate from `Spacing` because they describe a *visual element
/// dimension*, not a gap between elements.
public enum IconSize {
    /// 16pt — small inline icon (refresh button glyph slot).
    public static let sm: CGFloat = 16
    /// 22pt — compact avatar (per-account header inside aggregated
    /// mode where vertical real estate is at a premium).
    public static let md: CGFloat = 22
    /// 26pt — accounts-bar avatar (primary tappable target).
    public static let lg: CGFloat = 26
}

/// Corner-radius scale shared by all rounded shapes.
///
/// Kept short on purpose: the panel design is flat and uses small
/// radii. Reach for the system shape (`.capsule`, etc.) when the
/// element is meant to look pill-shaped — these tokens are for
/// rectangles only.
public enum Radius {
    /// 4pt — tiny chip / inline pill.
    public static let sm: CGFloat = 4
    /// 8pt — default for inline banners (toast, inline error).
    public static let md: CGFloat = 8
    /// 12pt — bigger surfaces (popovers, prominent cards).
    public static let lg: CGFloat = 12
}
