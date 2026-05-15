# Google Cloud — configuration OAuth pour LifeView

> Étape **manuelle**, à faire une seule fois sur le compte Google Cloud du
> développeur. Le `client_id` qui en sort est versionné dans le repo
> (project.yml + Info.plist) — c’est une valeur publique pour un client OAuth
> de type iOS/macOS, pas un secret.

## 1. Projet & API

LifeView est rattaché à un projet Google Cloud existant (« hub auth » qui
gère plusieurs apps perso). Aucun projet dédié n’est créé.

Pré-requis dans ce projet :

- **API Google Tasks** activée (`API & Services → Library → "Google Tasks
  API" → Enable`).

## 2. OAuth consent screen

À configurer une fois sur le projet :

| Champ                       | Valeur                                 |
| --------------------------- | -------------------------------------- |
| User type                   | `External`                             |
| App name                    | `LifeView`                             |
| User support email          | `hello@andreadelre.fr`                 |
| Developer contact email     | `hello@andreadelre.fr`                 |
| Publishing status           | `Testing` (Andrea ajouté en test user) |

Scopes ajoutés au consent screen :

- `https://www.googleapis.com/auth/tasks`

> Le scope `userinfo.email` / `userinfo.profile` n’est pas requis : le SDK
> Google Sign-In récupère le profil via l’ID token, pas via un appel
> `userinfo`.

## 3. OAuth Client ID

`API & Services → Credentials → Create credentials → OAuth client ID`.

| Champ              | Valeur                                                         |
| ------------------ | -------------------------------------------------------------- |
| Application type   | **iOS** (couvre macOS via `GoogleSignIn-iOS`)                  |
| Name               | `LifeView macOS`                                               |
| Bundle ID          | `fr.andreadelre.LifeView`                                      |
| App Store ID       | _vide_                                                         |
| Team ID            | _vide_ (à remplir en P7 lors de la notarization)               |

> Attention : ne **pas** créer un client de type « Desktop app ». Ce type
> utilise un flow OAuth de loopback redirect incompatible avec le SDK
> `GoogleSignIn-iOS`.

À l’issue, Google fournit :

- un **Client ID** : `<numero>-<hash>.apps.googleusercontent.com`
- un **iOS URL scheme** (reverse client ID) :
  `com.googleusercontent.apps.<numero>-<hash>`

Ces deux valeurs sont injectées dans le projet via XcodeGen
(`project.yml → info → properties`) :

- `GIDClientID` (clé Info.plist lue par le SDK)
- `CFBundleURLTypes[0].CFBundleURLSchemes[0]` (URL scheme nécessaire au
  callback de `ASWebAuthenticationSession`)

## 4. Rotation / révocation

- Le Client ID iOS n’expire pas. En cas de fuite, supprimer le client dans
  la Cloud Console — il sera invalidé immédiatement côté Google. Recréer un
  nouveau Client ID et mettre à jour `project.yml`.
- Les tokens utilisateur (access + refresh) sont stockés dans le Keychain
  de l’utilisateur final, jamais dans le repo. Voir `KeychainStore`.

## 5. Test users (phase `Testing`)

Tant que le consent screen reste en `Testing`, seuls les emails listés
dans la section « Test users » peuvent se connecter. Ajouter
`hello@andreadelre.fr` y suffit pour le dev. Le passage en `In production`
n’est requis qu’à partir de P7 si l’on souhaite distribuer hors test
users.
