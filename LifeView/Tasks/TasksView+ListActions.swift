import Core
import DesignSystem
import GoogleAuth
import SwiftUI

/// List CRUD entry points (create / rename / delete) presented as
/// `NSAlert`-backed modal prompts. Extracted from `TasksView.swift` to
/// keep the main view body under the SwiftLint `type_body_length`
/// budget — the alert plumbing is short but verbose enough to push
/// the struct over.
extension TasksView {
    func presentCreateList() {
        guard case .single = viewModel.selection else { return }
        guard let title = ConfirmationAlert.prompt(
            title: "Nouvelle liste",
            message: "Donne un nom à ta nouvelle liste de tâches.",
            placeholder: "Ex. Courses",
            confirmLabel: "Créer"
        ) else { return }
        _ = viewModel.createList(title: title)
    }

    func presentRenameList(_ list: TaskList) {
        guard case let .single(accountID) = viewModel.selection else { return }
        guard let newTitle = ConfirmationAlert.prompt(
            title: "Renommer la liste",
            placeholder: "Nom de la liste",
            initialValue: list.title,
            confirmLabel: "Renommer"
        ) else { return }
        viewModel.renameList(listID: list.id, to: newTitle, account: accountID)
    }

    func presentDeleteList(_ list: TaskList) {
        guard case let .single(accountID) = viewModel.selection else { return }
        let confirmed = ConfirmationAlert.confirm(
            title: "Supprimer « \(list.title) » ?",
            message: "Toutes les tâches de cette liste seront aussi supprimées. Cette action est irréversible.",
            confirmLabel: "Supprimer",
            isDestructive: true
        )
        guard confirmed else { return }
        viewModel.deleteList(listID: list.id, account: accountID)
    }
}
