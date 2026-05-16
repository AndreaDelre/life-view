# 001 — Cache disque + queue d'écritures sur GRDB

- **Statut** : accepté
- **Date** : 2026-05-16
- **Phase concernée** : P6.6 — Mode offline (issue #24)

## Contexte

P6.6 demande un **cache disque** pour les listes et tâches Google scopé
par compte, plus une **queue d'écritures persistante** drainée à la
reconnexion. Il faut choisir un moteur de persistance qui :

- s'intègre proprement avec Swift 6 strict-concurrency (`SWIFT_STRICT_CONCURRENCY = complete` à l'échelle du projet),
- ne fasse pas exploser le graphe de dépendances,
- expose une API testable sans plumberie spécifique,
- supporte une migration versionnée pour évoluer plus tard.

Deux options crédibles :

### A — CoreData

**Avantages** : framework Apple, schéma graphique (`.xcdatamodeld`),
beaucoup de tooling.

**Inconvénients**
- `NSManagedObjectContext` n'est pas `Sendable`. Sous strict-concurrency
  on tombe inévitablement sur du `@unchecked Sendable` (dette), du
  `perform`-block lourd (verbose), ou de l'isolation `@MainActor`
  partout (mauvais pour les performances).
- API impérative ancienne, beaucoup de KVC, peu d'async/await natif.
- Le schéma vit dans un fichier binaire `.xcdatamodeld` que les
  diffs de revue ne savent pas afficher proprement.

### B — GRDB (https://github.com/groue/GRDB.swift)

**Avantages**
- Sendable-first : `DatabaseQueue` et `DatabasePool` exposent
  `read { … }` / `write { … }` async, et les records sont des structs
  Codable.
- Migrations versionnées en quelques lignes (`DatabaseMigrator`).
- Aucune dépendance transitive autre que SQLite (déjà sur le système).
- Battle-tested : utilisé en production par Notion, Linear, plusieurs
  apps macOS de référence.
- Ajout SPM en une ligne, compatible Swift 6.

**Inconvénients** : on écrit nous-mêmes les `Record`s ; pas de visualiseur
graphique du schéma — acceptable vu la petite surface (3 tables).

## Décision

**On part sur GRDB (option B).**

Le critère décisif est l'alignement avec la stack Swift 6 strict
du projet : CoreData impose des compromis sur la concurrence pour chaque
lecture/écriture, GRDB est conçu pour ce monde.

## Conséquences

- Nouveau package SPM local `Packages/OfflineCache` qui dépend de
  `Core` (modèles domaine), `GoogleAuth` (`AccountID`) et `GRDB.swift`.
- Le schéma v1 (`lists`, `tasks`, `pending_writes`) est posé via un
  `DatabaseMigrator`. Toute évolution future est gérée par l'ajout d'une
  migration `vN` — pas de mutation ad hoc de la base.
- `OfflineCache` est un actor qui détient un `DatabaseQueue`. Les types
  publics renvoyés au reste de l'app sont les modèles `Core`
  (`TaskList`, `TaskItem`), jamais des records GRDB internes.
- Le wrapper expose deux modes de lecture :
  - synchrone via `OfflineCacheSnapshot` (struct `Sendable` lue au
    démarrage par `TasksViewModel` pour hydrater l'état avant tout
    appel réseau),
  - asynchrone via les méthodes de l'actor pour les mises à jour
    incrémentales.
- La queue d'écritures n'invalide pas la `SerialOperationQueue<AccountID>`
  en mémoire (P5) : elles cohabitent. La file mémoire sérialise les
  appels concurrents d'une même session ; la queue disque persiste les
  intentions à travers les redémarrages et les coupures réseau.
