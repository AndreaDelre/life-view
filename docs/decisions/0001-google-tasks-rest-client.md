# 0001 — Client REST maison pour Google Tasks (vs `GTLRTasks`)

- **Statut** : accepté
- **Date** : 2026-05-15
- **Phase concernée** : P3 — Lecture des Google Tasks (issue #4)

## Contexte

P3 demande de tranche entre deux implémentations pour `GoogleTasksClient` :

1. **`GTLRTasks`** — le client Objective-C officiel de Google, distribué via la famille `google-api-objectivec-client-for-rest`.
2. **Client REST maison** — `URLSession` + `Codable` directement sur les endpoints Google Tasks REST v1.

L'API `tasks.googleapis.com/v1` expose une surface très réduite (deux familles de ressources : `tasklists`, `tasks`, six endpoints au total : `list`, `get`, `insert`, `update`, `patch`, `delete`). Pour P3 on n'a besoin que de `tasklists.list` et `tasks.list`.

## Options

### A — `GTLRTasks`

**Avantages**
- Couvre l'ensemble de l'API.
- Modèles fournis, signature des erreurs côté serveur déjà mappée.
- Pagination cousue d'avance.

**Inconvénients**
- Pulls a large Objective-C dependency tree. The `GoogleSignIn-iOS` checkout that we already depend on for P2 brings ~7 transitive packages (`AppAuth-iOS`, `GTMAppAuth`, `gtm-session-fetcher`, `app-check`, `GoogleUtilities`, `promises`, `GoogleSignIn-iOS`) ; `GTLRTasks` ajoute le générateur `google-api-objectivec-client-for-rest` qui n'a pas de Swift Package Manager officiel maintenu activement (les forks SPM existent mais lag derrière).
- Modèles non `Sendable` : la liasse Obj-C utilise des `@property strong` mutables. Sous `SWIFT_STRICT_CONCURRENCY = complete` (cf. `CLAUDE.md`), ça impose des `@unchecked Sendable` ou des copies défensives partout.
- Bridge runtime via `GTLRService` + `GTLRQuery`, pas une API async/await native — chaque appel retombe sur des completion handlers à wrapper.
- Couplage fort à `GTMAppAuth` pour l'injection du token (qu'on n'utilise pas — notre `GoogleAccountStore` est la source de vérité). Forcer cette intégration revient à dupliquer la couche d'auth.

### B — Client REST maison

**Avantages**
- Surface API minuscule à couvrir (deux endpoints en lecture pour P3, quatre de plus en P5). Le coût d'écriture est inférieur au coût d'intégration de `GTLRTasks`.
- 100 % Swift, `Sendable` "by construction", aucun pont Obj-C, aucune dépendance à ajouter au graphe SPM.
- Contrôle total de l'injection du token : on s'appuie directement sur le `GoogleAccountStore` existant via une protocol `TasksAuthorizing`.
- Stratégie de retry sur 401 (refresh + rejouer la requête une fois) explicite et testable, alignée sur ce que demande l'issue.
- Tests unitaires triviaux : on stube un `TasksHTTPClient` (même seam que `HTTPClient` côté `GoogleAuth`) sans toucher au réseau.

**Inconvénients**
- On écrit nous-mêmes les DTOs (`Codable`) et la pagination (`pageToken`). Coût modéré, et de toute façon nécessaire pour transformer en modèles domaine.
- Si l'API évolue (nouveaux champs), on les ajoute à la main. Acceptable vu la stabilité de l'API Tasks v1 (pas d'évolution majeure depuis ~2018).

## Décision

**On part sur le client REST maison (option B).**

Le critère décisif est l'alignement avec la stack Swift 6 strict-concurrency du projet et la volonté de garder un graphe de dépendances minimal. La surface API à couvrir ne justifie pas d'introduire un client Obj-C générique pour économiser ~200 lignes de DTO + endpoints.

## Conséquences

- `GoogleTasksClient` expose `TasksAuthorizing` (protocole) pour récupérer un access token et déclencher un refresh forcé. Le wiring concret avec `GoogleAccountStore` vit dans la couche app (`LifeView/Tasks/…`).
- `GoogleAccountStore` gagne une méthode `forceRefreshAccessToken()` pour permettre la stratégie de retry sur 401 — sans ça, `validAccessToken()` ne refait un refresh que si le token est expiré côté horloge.
- Les DTOs (`RemoteTaskList`, `RemoteTask`) restent **internes** au package. Seuls les types domaine de `Core` (`TaskList`, `TaskItem`, `TaskStatus`) traversent la frontière. Cf. critère de l'issue : "Aucun type Google ne fuit hors du package `GoogleTasksClient`".
- En P5 (écritures), on étend le même socle (`POST`, `PATCH`, `DELETE`). En P4 (multi-comptes), `TasksAuthorizing` reçoit un `accountID` ou est instancié par compte — détail à trancher en P4.
