import AppKit

/// Thin wrapper around `NSAlert` for the modal confirmation flows
/// (P5: list deletion). Lives in `DesignSystem` so the call-site
/// doesn't reach for AppKit directly; the look stays native and
/// consistent with system alerts.
@MainActor
public enum ConfirmationAlert {
    /// Presents a modal confirm/cancel alert and returns whether the
    /// user confirmed. `isDestructive` highlights the confirm button
    /// with the system's destructive style — used for delete flows.
    public static func confirm(
        title: String,
        message: String? = nil,
        confirmLabel: String,
        cancelLabel: String = "Annuler",
        isDestructive: Bool = false
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        if let message {
            alert.informativeText = message
        }
        let confirmButton = alert.addButton(withTitle: confirmLabel)
        alert.addButton(withTitle: cancelLabel)
        if isDestructive {
            confirmButton.hasDestructiveAction = true
        }
        return alert.runModal() == .alertFirstButtonReturn
    }
}
