# TP 3.6 – Projet Multibranch : un pipeline par branche

**Objectif :** reproduire le flux de travail d'une équipe : chaque branche et chaque *pull request* est testée automatiquement, seule la branche `main` publie une image, et une PR rouge ne peut pas être fusionnée.

**Statut :** ✅ réalisé et vérifié (sauf webhook, voir plus bas) – preuves dans [`preuves/`](preuves/)
**Dépôt :** [nedstudio237-cmd/legeni-webapp](https://github.com/nedstudio237-cmd/legeni-webapp) – PR [#1](https://github.com/nedstudio237-cmd/legeni-webapp/pull/1) (verte, fusionnée), PR [#2](https://github.com/nedstudio237-cmd/legeni-webapp/pull/2) (rouge, bloquée)

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`Jenkinsfile`](Jenkinsfile) | Push uniquement sur `main` (`when { branch 'main' }`), version par branche, noms de conteneur/réseau de test uniques par branche |
| [`job-legeni-webapp-mb.xml`](job-legeni-webapp-mb.xml) | Job *Multibranch Pipeline* : source GitHub, découverte des branches et des PR, scan toutes les minutes |

## Commandes et rôle

### Jenkinsfile
| Élément | Rôle |
|---|---|
| `when { allOf { branch 'main'; expression { params.PUSH } } }` | Le stage Push ne s'exécute que sur `main` |
| `VERSION = "${env.BRANCH_NAME == 'main' ? '1.0.' + env.BUILD_NUMBER : env.BRANCH_NAME.replaceAll(…) + '-' + env.BUILD_NUMBER}"` | `1.0.N` sur `main`, `feature-couleur-N` sur une branche |
| `env.BRANCH_NAME` | Variable fournie par le multibranch : nom de la branche (ou `PR-1`) |

### Jenkins
| Action | Rôle |
|---|---|
| **Credentials** → *Username with password*, ID `github` (identifiant + Personal Access Token) | Accès à l'API GitHub (évite la limite de 60 appels/heure, publie les statuts dans les PR) |
| **Nouvel item → Multibranch Pipeline** → source **GitHub** | Un sous-job par branche et par PR, créé automatiquement |
| *Discover branches* + *Discover pull requests from origin* | Quelles branches/PR construire |
| *Script Path* `Jenkinsfile` | Chaque branche utilise son propre Jenkinsfile |
| *Periodically if not otherwise run* : 1 minute | Rescanne le dépôt chaque minute (filet de sécurité sans webhook) |
| **Scan Repository Now** | Lance un scan immédiat |

### Git / GitHub
| Commande | Rôle |
|---|---|
| `git checkout -b feature/couleur` | Crée une branche de travail |
| `sed -i 's/#1f6feb/#8250df/' app.py` | Change la couleur par défaut |
| `git commit -am "…" && git push -u origin feature/couleur` | Publie la branche → un sous-job `feature/couleur` apparaît |
| GitHub → **New pull request** `feature/couleur` → `main` | Ouvre une PR → sous-job `PR-1`, statut Jenkins affiché dans la PR |
| GitHub → **Merge pull request** | Fusionne → le build de `main` publie l'image |
| GitHub → **Settings → Rules → Rulesets** (cible : branche par défaut, *Require status checks* `continuous-integration/jenkins/pr-merge`, *Active*) | Protège `main` : une PR rouge ne peut pas être fusionnée |
| `git push origin --delete feature/test-rouge` | Supprime une branche distante |

## Résultats obtenus
- Scan : sous-job **main** créé, build #1 vert, image `1.0.1` publiée.
- **feature/couleur** #1 : vert, version `feature-couleur-1`, `Stage "Push Docker Hub" skipped due to when conditional` → **rien publié**.
- **PR-1** #1 : vert ; statuts dans la PR GitHub : `continuous-integration/jenkins/pr-merge success – This commit looks good`.
- Merge de la PR #1 → **main** #2 : `Merge pull request #1 …`, image `1.0.2` publiée.
- Protection de `main` (ruleset actif, check `continuous-integration/jenkins/pr-merge` exigé) → PR #2 avec test cassé : build **rouge** (`AssertionError: assert {'status': 'ko'} == {'status': 'ok'}`), statut `error` dans la PR, `mergeable_state : blocked` → **fusion impossible**. PR #2 fermée ensuite.
- Remarque : la numérotation du multibranch repart de 1, le tag `1.0.1` du TP 3.5 a été réécrit par `main` #1.

### Étape 5 (webhook) : non réalisée
Le webhook nécessite d'exposer Jenkins sur Internet via un tunnel (smee.io / ngrok). Choix fait de **ne pas exposer** le Jenkins de la VM. Le scan périodique (1 minute) déclenche quand même les builds, avec au plus 1 minute de délai au lieu de quelques secondes.
Ce qu'il aurait fallu faire : `npx smee-client --url https://smee.io/<canal> --target http://localhost:8080/github-webhook/`, puis GitHub → **Settings → Webhooks → Add webhook** (Payload URL `https://smee.io/<canal>`, `application/json`, événements *push* et *pull requests*) et vérifier un code **200** dans *Recent Deliveries*.

## À retenir
- **Multibranch** = un pipeline par branche/PR, découverts automatiquement ; le Jenkinsfile de chaque branche est utilisé.
- **Seule `main` livre** : les branches et PR sont testées mais ne publient rien.
- **Statut dans la PR + règle de protection** = une PR rouge ne peut pas être fusionnée : la CI devient une vraie porte de qualité.
- **Webhook** = déclenchement instantané (push GitHub → Jenkins) ; **scan périodique** = filet de sécurité si le webhook n'arrive pas.
