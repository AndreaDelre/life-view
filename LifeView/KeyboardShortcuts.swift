import SwiftUI

/// Central registry of every keyboard shortcut bound inside the panel.
///
/// Two responsibilities:
///
/// 1. Provide the canonical `KeyboardShortcut` instances used by SwiftUI
///    `.keyboardShortcut(...)` bindings — so a rebind only needs to
///    touch this file.
/// 2. Provide the human-readable table consumed by ``HelpOverlayView``
///    to render the cheat-sheet. Each row references the same
///    ``Shortcut`` it documents, so the label shown to the user and
///    the binding actually wired are guaranteed to stay in sync.
///
/// App-specific by design: lives in the app target rather than `Core`
/// because every shortcut is panel-bound; no SPM package needs to know
/// about them. P7 will likely introduce a user-customisable layer on
/// top of this table — that work belongs in the app target too.
enum Shortcut {
    // MARK: - Edition

    /// Focus the new-task field.
    static let newTask = KeyboardShortcut("n", modifiers: [])
    /// Validate inline edit / create the pending task.
    /// Bound via `.onSubmit` / `.onKeyPress(.return)` rather than a
    /// `KeyboardShortcut`, because Return is context-dependent (it must
    /// only fire when a row is selected or the new-task field is
    /// focused — never when the help bubble or a menu is open).
    static let returnKey = "Return"
    /// Cancel current edit / close the help bubble / close the panel.
    /// Cascaded by ``Shortcut/handleEscape`` at call site.
    static let escapeKey = "Esc"
    /// Delete the selected task.
    static let deleteKey = "Suppr / ⌘⌫"
    /// Toggle completion of the selected task.
    static let spaceKey = "Espace"

    // MARK: - Navigation

    /// Move selection up.
    static let upKey = "↑"
    /// Move selection down.
    static let downKey = "↓"

    // MARK: - Lists

    /// Cmd+1 … Cmd+9 — switch to the Nth list of the current account.
    /// SwiftUI binds each one explicitly inside ``TasksView`` (a single
    /// `ForEach` over invisible buttons keeps the modifier table compact).
    static func switchList(_ index: Int) -> KeyboardShortcut {
        precondition((1...9).contains(index), "switchList index out of range")
        let character = Character(String(index))
        return KeyboardShortcut(KeyEquivalent(character), modifiers: .command)
    }

    // MARK: - Accounts

    /// Cycle to the next account. In aggregated mode, bounces to the
    /// first single account so the user always lands on a concrete
    /// selection.
    static let cycleAccount = KeyboardShortcut("a", modifiers: [.command, .shift])

    // MARK: - Help

    /// Show or hide the keyboard-shortcut help overlay.
    ///
    /// `?` on a US/EN keyboard is `Shift+/`. SwiftUI's
    /// `KeyboardShortcut("?")` honours the literal character, so the
    /// binding works regardless of the modifier the user actually
    /// presses — the system normalises it for us.
    static let toggleHelp = KeyboardShortcut("?", modifiers: [])
}

// MARK: - Help table

/// One displayable cheat-sheet entry. `keys` is intentionally a free
/// string (not a `KeyboardShortcut`) so we can document keys that
/// aren't bound via SwiftUI's modifier API (Return, Space, arrows, the
/// Cmd+1…9 range as a single row, etc.).
struct ShortcutEntry: Identifiable {
    let keys: String
    let label: String
    var id: String { keys + label }
}

struct ShortcutSection: Identifiable {
    let title: String
    let entries: [ShortcutEntry]
    var id: String { title }
}

enum ShortcutCatalog {
    static let sections: [ShortcutSection] = [
        ShortcutSection(
            title: "Édition",
            entries: [
                ShortcutEntry(keys: "N", label: "Nouvelle tâche"),
                ShortcutEntry(keys: "⌘N", label: "Nouvelle tâche (focus champ)"),
                ShortcutEntry(keys: "↩︎", label: "Valider / éditer la tâche sélectionnée"),
                ShortcutEntry(keys: "⎋", label: "Annuler l’édition ou fermer le panel"),
                ShortcutEntry(keys: "Espace", label: "Marquer la tâche terminée / à faire"),
                ShortcutEntry(keys: "⌫ / ⌘⌫", label: "Supprimer la tâche sélectionnée"),
            ]
        ),
        ShortcutSection(
            title: "Navigation",
            entries: [
                ShortcutEntry(keys: "↑ / ↓", label: "Changer de tâche sélectionnée"),
            ]
        ),
        ShortcutSection(
            title: "Listes",
            entries: [
                ShortcutEntry(keys: "⌘1 … ⌘9", label: "Aller à la Nᵉ liste du compte courant"),
            ]
        ),
        ShortcutSection(
            title: "Comptes",
            entries: [
                ShortcutEntry(keys: "⌘⇧A", label: "Compte suivant"),
            ]
        ),
        ShortcutSection(
            title: "Aide",
            entries: [
                ShortcutEntry(keys: "?", label: "Afficher / masquer cette aide"),
            ]
        ),
    ]
}
