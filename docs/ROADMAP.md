# Roadmap LifeView

Découpage par phases. Chaque phase produit un livrable testable de bout en bout. On ne passe à la suivante qu'une fois la précédente verte (lint + tests + revue manuelle).

---

## P0 — Fondations (squelette technique)

**Objectif :** un projet Xcode qui compile, des packages SPM vides mais reliés, du lint, et de la CI.

- [ ] Installer dépendances de dev : `xcodegen`, `swiftlint`, `swiftformat` (`brew bundle` avec un `Brewfile`).
- [ ] Écrire `project.yml` XcodeGen :
  - target app `LifeView` (macOS 14+, SwiftUI lifecycle, App Sandbox, Hardened Runtime, entitlements vides pour l'instant).
  - configurations `Debug` / `Release` via `.xcconfig`.
- [ ] Créer les packages SPM locaux : `Core`, `GoogleAuth`, `GoogleTasksClient`, `DesignSystem`.
- [ ] Brancher SwiftLint + SwiftFormat (config + scripts de pre-commit optionnel).
- [ ] Workflow GitHub Actions : `lint` + `build` + `test` sur `macos-14`.
- [ ] README "Démarrer" testé sur une machine vierge.

**Critère de sortie :** `xcodegen generate && xcodebuild -scheme LifeView build test` passe. CI verte.

---

## P1 — Coquille d'application (volet coulissant gauche)

**Objectif :** une fenêtre `NSPanel` qui glisse depuis le bord gauche, sans aucune donnée.

- [ ] `LifeViewPanel: NSPanel` configurée : `.nonactivatingPanel`, `.utilityWindow`, niveau `.statusBar`, masquée du Mission Control, présente sur tous les espaces.
- [ ] Géométrie : largeur fixe (~380 pt), pleine hauteur de l'écran actif, ancrée à gauche.
- [ ] Animation open/close (`NSAnimationContext`, courbe `easeOut`, ~220 ms).
- [ ] Déclencheurs :
  - icône `NSStatusItem` dans la barre de menu (toggle).
  - hotkey global configurable (par défaut `⌥⌘L`), via Carbon Hot Keys ou `MASShortcut`.
- [ ] Auto-close au clic hors panel (suivi via `NSEvent.addGlobalMonitorForEvents`).
- [ ] Vue SwiftUI placeholder (titre + état vide).
- [ ] Préférences de base : choix de l'écran si multi-écran, raccourci.

**Critère de sortie :** le volet s'ouvre / se ferme de manière fluide, ne vole pas le focus, marche en multi-écran.

---

## P2 — Authentification Google (un seul compte)

**Objectif :** se connecter à un compte Google et stocker son token.

- [ ] Console Google Cloud : créer OAuth Client ID "macOS" + activer Tasks API.
- [ ] Intégrer `GoogleSignIn-iOS` côté `GoogleAuth`.
- [ ] Flow OAuth via `ASWebAuthenticationSession`.
- [ ] Wrapper `KeychainStore` (générique, scope par `accountID`).
- [ ] Persister `idToken` + `refreshToken` + profil minimal (email, nom, avatar URL).
- [ ] Auto-refresh transparent (intercepteur sur l'API client).
- [ ] UI : écran "Pas de compte" avec bouton "Se connecter à Google".
- [ ] Déconnexion (révocation côté Google + purge Keychain).

**Critère de sortie :** ouvrir l'app, se connecter, fermer l'app, rouvrir → toujours connecté.

---

## P3 — Lecture des Google Tasks

**Objectif :** afficher les listes et les tâches du compte connecté.

- [ ] `GoogleTasksClient` : wrapper async/await autour de `GTLRTasks` (`fetchTaskLists`, `fetchTasks(listID:)`).
- [ ] Modèle domaine : `TaskList`, `TaskItem`, `TaskStatus` (zéro fuite Google).
- [ ] ViewModel `TasksViewModel` : chargement, états (`idle/loading/loaded/error`), refresh.
- [ ] Vue principale : sélecteur de liste + liste des tâches (`List` SwiftUI, swipe actions à venir en P5).
- [ ] Mise en cache mémoire + invalidation au pull-to-refresh (`refreshable`).
- [ ] États vides + erreurs (réseau, 401 → refresh).

**Critère de sortie :** je vois en temps réel les mêmes tâches que sur tasks.google.com pour mon compte.

---

## P4 — Multi-comptes

**Objectif :** gérer N comptes Google, basculer entre eux, voir les listes de tous.

- [ ] `AccountStore` (Swift actor) : ajoute / retire / liste les comptes, source de vérité.
- [ ] Keychain segmenté par `accountID` (un trousseau d'entrées par compte).
- [ ] UI :
  - barre supérieure du panel avec avatars des comptes + bouton "+".
  - écran "Comptes" dans les Préférences (liste, ajout, suppression).
- [ ] Stratégie d'affichage des tâches :
  - vue "compte courant" (filtrée).
  - vue "tous les comptes" (agrégée, groupée par compte puis par liste).
- [ ] Token refresh indépendant par compte, avec backoff.

**Critère de sortie :** je connecte deux comptes Google, je vois leurs tâches respectives, je passe de l'un à l'autre en un clic.

---

## P5 — Écriture (création, complétion, édition, suppression)

**Objectif :** rendre l'app utilisable au quotidien.

- [ ] Création de tâche (champ de saisie en haut, `⌘N`, support de la date d'échéance).
- [ ] Complétion (checkbox + swipe + raccourci).
- [ ] Édition inline (double-clic / `Return`).
- [ ] Suppression (`⌫`).
- [ ] Sync optimiste : UI met à jour immédiatement, rollback en cas d'erreur.
- [ ] Création / renommage / suppression de listes.

**Critère de sortie :** je remplace tasks.google.com pour mon usage perso pendant 1 semaine sans frustration.

---

## P6 — UX polish

- [ ] Drag-to-reorder des tâches (avec persistance via `position`).
- [ ] Raccourcis clavier exhaustifs et bulle d'aide.
- [ ] Animations : ajout, complétion (rayure + fade), suppression.
- [ ] Mode sombre / clair parfait.
- [ ] État offline (lecture depuis le cache, queue d'écritures).
- [ ] Notifications natives pour les tâches avec date d'échéance (opt-in).
- [ ] Accessibilité : VoiceOver, navigation clavier complète, Dynamic Type.

---

## P7 — Réglages & distribution

- [ ] Fenêtre Préférences (SwiftUI `Settings` scene) : raccourci, démarrage auto (`SMAppService`), écran préféré, thème, comptes.
- [ ] Code signing Developer ID + notarisation + stapling.
- [ ] Auto-update via [Sparkle](https://sparkle-project.org/) (optionnel).
- [ ] DMG signé pour distribution hors App Store.
- [ ] Page de release (CHANGELOG, screenshots).

---

## Hors scope (pour l'instant)

- Intégration iCloud, Reminders, Things, Todoist…
- Vue calendrier / Gantt.
- Synchronisation entre appareils (l'app vit sur le Mac, point).
- Plugins / extensions tierces.

On y reviendra si — et seulement si — les phases P0→P5 sont solides et utilisées.
