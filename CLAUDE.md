# CLAUDE.md — contexte projet LifeView

> Fichier lu automatiquement par tout agent Claude Code travaillant dans ce repo. Il complète `~/.claude/CLAUDE.md` (règles personnelles globales : branche dédiée, pas de push sans autorisation explicite, pas de co-auteur). Ne pas dupliquer ces règles ici.

## Vision

Application **native macOS** qui ouvre un volet sur le **bord gauche** de l'écran (symétrique du centre de notifications) pour piloter ses **Google Tasks multi-comptes** sans changer de fenêtre. Cible : power-user qui jongle entre comptes Google perso / pro.

## Stack (non négociable sans discussion)

| Domaine          | Choix                                                          |
| ---------------- | -------------------------------------------------------------- |
| Langage          | **Swift 6**, `SWIFT_STRICT_CONCURRENCY = complete`             |
| UI               | SwiftUI pour les vues, AppKit (`NSPanel`) pour la fenêtre      |
| Déploiement      | macOS 14 Sonoma minimum, universel (arm64 + x86_64)            |
| Auth Google      | `GoogleSignIn-iOS` (supporte macOS)                            |
| API Tasks        | À trancher en P3 : `GTLRTasks` officiel ou client REST maison  |
| Stockage tokens  | Keychain (Security framework), scopé par compte                |
| Génération Xcode | **XcodeGen** (`project.yml` versionné, `.xcodeproj` régénéré)  |
| Modules          | App + 4 packages SPM locaux : `Core`, `GoogleAuth`, `GoogleTasksClient`, `DesignSystem` |
| Tests            | XCTest (par package, exécutés via `xcodebuild test`)           |
| Lint / format    | SwiftLint `--strict` (bloquant), SwiftFormat                   |
| CI               | GitHub Actions sur `macos-14`                                  |
| Bundle ID        | `fr.andreadelre.LifeView`                                      |

## Layout du repo

```
.
├── LifeView/                    Source de l'app (SwiftUI lifecycle, entitlements)
├── Packages/                    Packages SPM locaux
│   ├── Core/                    Modèles, protocoles, types partagés
│   ├── GoogleAuth/              OAuth, Keychain, multi-comptes
│   ├── GoogleTasksClient/       Wrapper API Tasks, modèles domaine
│   └── DesignSystem/            Tokens, composants SwiftUI réutilisables
├── Config/                      xcconfig (Shared / Debug / Release)
├── .github/workflows/           CI
├── docs/                        ROADMAP.md + docs annexes
├── project.yml                  Spec XcodeGen
├── Brewfile                     Outils de dev requis
├── .swiftlint.yml               Config SwiftLint stricte
└── .swiftformat                 Config SwiftFormat
```

`LifeView.xcodeproj` est **généré localement**, jamais versionné (déjà dans `.gitignore`).

## Conventions

- **Branches** : `feat/`, `fix/`, `chore/`, `refactor/`, `docs/`, `test/`, `ci/`. Une PR par phase de la roadmap quand c'est possible.
- **Commits** : [Conventional Commits](https://www.conventionalcommits.org/) (`feat(panel): slide-in animation`). Découpés en unités logiques.
- **PR** : titre = ligne de résumé du commit principal. Le corps **doit** lier l'issue qu'elle ferme (`Closes #N`).
- **Pas de** : `.xcodeproj` commité, fichiers générés (`.build/`, `DerivedData/`, `Package.resolved` racine), secrets (`GoogleService-Info.plist`, `ClientSecret.plist`).
- **Lint bloquant** : `swiftlint --strict` doit passer avant tout commit. La CI le bloque de toute façon.

## Vérification en local (avant de pousser)

```bash
brew bundle                                              # xcodegen, swiftlint, swiftformat
xcodegen generate                                        # → LifeView.xcodeproj
swiftlint --strict                                       # 0 violation attendu
xcodebuild -scheme LifeView -destination 'platform=macOS' build test
```

Si l'une de ces commandes échoue, **corriger** avant de rendre la main.

## Règles spécifiques aux délégations à un sous-agent

Quand tu es un sous-agent (sub-agent Claude Code) lancé sur une issue par l'orchestrateur :

1. Tu travailles sur la **branche indiquée dans le brief** (typiquement `feat/pX-<nom>`).
2. Tu **commits** par unités logiques en Conventional Commits.
3. Tu **ne push pas**, tu **n'ouvres pas de PR**. C'est le rôle de l'orchestrateur après revue de ton diff.
4. Tu lances les 4 vérifications locales ci-dessus et **reportes leur résultat** dans ton rapport final.
5. Ton **rapport final** est court (≤ 300 mots) et structuré : branche, fichiers ajoutés, décisions notables, résultats des vérifications, anomalies à valider.
6. Si tu prends une décision technique non triviale (naming, architecture interne d'un module, choix d'API), tu la **documentes** dans le commit concerné et la **signales** dans le rapport.
7. Si tu es **bloqué** sur une décision qui dépasse ton brief, tu rends la main sans inventer — l'orchestrateur tranchera.

## Pointeurs

- **Roadmap globale** : [`docs/ROADMAP.md`](docs/ROADMAP.md)
- **Specs détaillées par phase** : issues GitHub `phase:P0` → `phase:P7`
- **Projet de suivi** : [Personnal Project](https://github.com/users/AndreaDelre/projects/1)

## Hors-scope général

Pas d'Electron, pas de WebView, pas de backend tiers, pas de sync inter-appareils, pas d'intégration Reminders/Things/Todoist. L'app vit sur le Mac, pilote Google Tasks, point. Tant que les phases P0→P5 ne sont pas solides, on n'élargit pas.
