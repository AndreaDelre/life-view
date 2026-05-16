import CoreGraphics

/// 4-point spacing scale used by every padding / stack in the app.
///
/// All values are powers/multiples of 4 so vertical rhythm stays
/// predictable when sub-views compose. Use the named tokens rather
/// than hard-coding magic numbers in views.
public enum Spacing {
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
