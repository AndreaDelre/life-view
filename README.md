# LifeView

> Volet latéral natif macOS pour piloter ses Google Tasks (multi-comptes) depuis le bord gauche de l'écran.

## Vision

Le centre de notifications de macOS s'ouvre par le bord droit. **LifeView** ouvre un volet symétrique sur le bord **gauche** : un espace personnel pour consulter, ajouter et compléter ses tâches Google sans changer de fenêtre.

Cible : utilisateur power-user macOS qui jongle entre plusieurs comptes Google (perso / pro / projets) et veut un seul endroit pour les tâches.

## Principes

- **Natif d'abord.** Pas d'Electron, pas de WebView. SwiftUI + AppKit pour la fenêtre.
- **Qualité de code.** Modules SPM, concurrence stricte Swift 6, tests, lint, CI.
- **Performance perçue.** Animation 60 fps, fenêtre pré-rendue, sync optimiste.
- **Vie privée.** Tokens OAuth chiffrés dans le Keychain par compte. Pas de backend tiers.
- **Sobre.** Une fonction principale bien faite avant d'en empiler d'autres.

## Stack technique

| Domaine            | Choix                                                                 |
| ------------------ | --------------------------------------------------------------------- |
| Langage            | Swift 6 (mode `complete` de concurrence stricte)                      |
| UI                 | SwiftUI pour les vues, AppKit (`NSPanel`) pour la fenêtre coulissante |
| Cible              | macOS 14 Sonoma minimum, universel (arm64 + x86_64)                   |
| Auth Google        | [`GoogleSignIn-iOS`](https://github.com/google/GoogleSignIn-iOS) (supporte macOS) |
| API Google Tasks   | [`google-api-objectivec-client-for-rest`](https://github.com/google/google-api-objectivec-client-for-rest) (`GTLRTasks`) |
| Stockage tokens    | Keychain (Security framework) via wrapper Swift maison                |
| Architecture       | MVVM + service layer, modules SPM locaux                              |
| Génération projet  | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml` versionné, `.xcodeproj` régénéré) |
| Tests              | Swift Testing (unitaires) + XCTest (UI / intégration)                 |
| Qualité            | SwiftLint, SwiftFormat, `swift package diagnose-api-breaking-changes` |
| CI                 | GitHub Actions (lint + build + tests sur macOS)                       |
| Distribution       | App Sandbox + Hardened Runtime + notarisation (Developer ID)          |

## Architecture (cible)

```
LifeView/                       (app target — coquille SwiftUI/AppKit)
├── App/                        Cycle de vie, NSApplicationDelegate, gestion du panel
├── Panel/                      NSPanel custom, animation, déclenchement bord d'écran
├── Features/
│   ├── Tasks/                  Vues + ViewModels des listes de tâches
│   ├── Accounts/               UI multi-comptes (ajout, sélecteur, retrait)
│   └── Settings/               Préférences
└── Resources/                  Assets, Info.plist, entitlements

Packages/
├── Core/                       Modèles, protocoles, types partagés (zéro UI)
├── GoogleTasksClient/          Wrapper de GTLRTasks (async/await, typé domaine)
├── GoogleAuth/                 OAuth multi-comptes, refresh, Keychain
└── DesignSystem/               Tokens, composants SwiftUI réutilisables
```

Le découpage en packages SPM accélère les compilations incrémentales et rend chaque morceau testable en isolation.

## Démarrer

Pré-requis : macOS 14 Sonoma minimum, Xcode 15+ (Command Line Tools acceptées pour la CI), [Homebrew](https://brew.sh).

```bash
# 1. Installer les outils de dev (xcodegen, swiftlint, swiftformat)
brew bundle

# 2. Générer le projet Xcode (le .xcodeproj n'est pas versionné)
xcodegen generate

# 3. Compiler et tester en ligne de commande
xcodebuild -scheme LifeView -destination 'platform=macOS' build test

# 4. Ou ouvrir dans Xcode pour développer
open LifeView.xcodeproj
```

Lint :

```bash
swiftlint --strict     # 0 warning attendu
swiftformat .          # auto-format
```

Les configurations partagées vivent dans `Config/*.xcconfig`. Les packages SPM
locaux (`Core`, `GoogleAuth`, `GoogleTasksClient`, `DesignSystem`) sont sous
`Packages/` et liés automatiquement au target `LifeView` via `project.yml`.

## Conventions Git

- `main` est protégée. Tout passe par PR depuis une branche dédiée.
- Préfixes : `feat/`, `fix/`, `chore/`, `refactor/`, `docs/`, `test/`.
- Messages de commit en style [Conventional Commits](https://www.conventionalcommits.org/) : `feat(panel): slide-in animation`.
- Pas de force-push sur `main`.

## Licence

À définir (probablement MIT pour le code, droits d'usage de l'app à part).
