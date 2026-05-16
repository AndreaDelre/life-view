import SwiftUI

/// Semantic motion tokens.
///
/// Three named animations cover the vocabulary the app actually uses:
/// a snappy micro-interaction (`quick`), a default UI transition
/// (`standard`), and a more pronounced state change (`emphasised`).
/// Every animated state change in the app should reach for one of
/// these rather than spelling out a literal `.easeInOut(duration:)`
/// — keeping the catalogue small means we can re-tune the app's whole
/// feel from a single file.
///
/// Implementation notes
/// --------------------
/// * Curves are SwiftUI's built-in `.easeOut` / `.easeInOut`. They
///   look right on macOS and avoid pulling in a `.spring` that bounces
///   in places where a flat panel UI should feel calm.
/// * Durations are deliberately short. The panel is a fast-access
///   surface, not a marketing splash; anything > 0.3s starts to feel
///   sluggish for power-users tapping the hotkey to triage tasks.
public enum Motion {
    // MARK: - Durations (seconds)

    /// 0.12s — sub-frame-perceptible micro-interactions (icon flip,
    /// hover tint).
    public static let durationQuick: Double = 0.12
    /// 0.20s — default for list inserts / deletes / state toggles.
    public static let durationStandard: Double = 0.20
    /// 0.28s — emphasised state changes (completion strike-through,
    /// slide-out on delete).
    public static let durationEmphasised: Double = 0.28

    // MARK: - Animations

    /// Snappy ease-out for tiny UI affordances.
    public static let quick: Animation = .easeOut(duration: durationQuick)
    /// Default ease-in-out for most state transitions.
    public static let standard: Animation = .easeInOut(duration: durationStandard)
    /// Slightly longer ease-in-out for richer transitions (slide-out
    /// on delete, strike-through propagation on completion).
    public static let emphasised: Animation = .easeInOut(duration: durationEmphasised)

    /// Cross-fade fallback used when
    /// `@Environment(\.accessibilityReduceMotion)` is on. Same timing
    /// as `standard` so the rhythm of the app doesn't change, only the
    /// movement vector is dropped.
    public static let reduced: Animation = .easeInOut(duration: durationStandard)
}
