# TP 3.2 – Projet build : premier job freestyle paramétré

**Objectif :** construire à la main un job *freestyle* qui récupère le code du site `restaurant` sur GitHub, construit une image Docker et lance le site. Explorer workspace, console, paramètres, variables d'environnement et déclencheurs.

**Statut :** ✅ réalisé et vérifié – preuves dans [`preuves/`](preuves/)

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`job-build.xml`](job-build.xml) | Configuration complète du job `build` (paramètres, Git, Poll SCM, script) |
| [`build.sh`](build.sh) | Script shell du job (étape de build), avec l'étape 7 et le défi |

**Paramètres du job :** `IMAGE_NAME=restaurant`, `IMAGE_TAG=latest`, `Votre_ID_Github=Legeni07`, `PORT` (choix 8092/8093/8094, défi), `NETTOYER` (booléen, défi).
**Code source :** `https://github.com/${Votre_ID_Github}/restaurant.git`, branche `*/main`.

## Commandes et rôle

### Dans le script du job
| Commande | Rôle |
|---|---|
| `set -euo pipefail` | Arrête le job à la première erreur (sinon un build raté peut finir « vert ») |
| `echo "== Build n°${BUILD_NUMBER} du commit ${GIT_COMMIT:0:7} dans ${WORKSPACE}"` | Affiche des variables fournies par Jenkins : n° de build, commit cloné, dossier de travail |
| `echo "Job ${JOB_NAME}, URL ${BUILD_URL}"` | Étape 7 : autres variables d'environnement Jenkins |
| `cat > Dockerfile <<'EOT' … EOT` | Génère le Dockerfile (nginx + `COPY` du code cloné par Jenkins) |
| `printf '.git\nDockerfile\n' > .dockerignore` | Exclut ces fichiers de l'image |
| `docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -t ${IMAGE_NAME}:build-${BUILD_NUMBER} .` | Construit l'image avec 2 tags : `latest` et un tag unique par build |
| `docker images ${IMAGE_NAME}` | Liste les images construites |
| `docker rm -f legeni_website 2>/dev/null \|\| true` | Supprime le conteneur du build précédent → job **idempotent** |
| `docker run --name legeni_website -d -p ${PORT}:80 ${IMAGE_NAME}:${IMAGE_TAG}` | Lance le site sur le port choisi |
| `docker ps --filter name=legeni_website` | Vérifie que le conteneur tourne |
| `docker images … \| grep '^build-' \| sort -t- -k2 -n -r \| tail -n +4 \| xargs -r -I{} docker rmi …` | Défi : supprime les images `build-*` sauf les 3 plus récentes |

### Pour vérifier
| Commande | Rôle |
|---|---|
| `curl -s localhost:8092 \| grep title` | Le site restaurant répond (`<title>Restaurant</title>`) |
| `docker exec jenkins ls /var/jenkins_home/workspace/build` | Contenu de l'espace de travail du job |
| `docker images restaurant` | Tags `latest` et `build-<n>` |

### Dans Jenkins
| Action | Rôle |
|---|---|
| **Lancer un build avec des paramètres** | Exécuter le job avec des valeurs choisies |
| **Console Output** | Journal complet du build : premier outil de diagnostic |
| **Espace de travail** | Fichiers clonés et générés par le build |
| **Poll SCM** `H/2 * * * *` | Jenkins interroge GitHub toutes les 2 min et lance un build s'il y a un nouveau commit |
| `http://localhost:8080/env-vars.html` | Liste des variables d'environnement disponibles |

## Résultats obtenus
- Build #1 : clone de `Legeni07/restaurant` (commit `1a25da7`), image `restaurant:latest` + `restaurant:build-1`, site sur `http://localhost:8092` → **SUCCESS**
- Build #3 (ligne `docker rm -f` retirée) → **FAILURE** : `Conflict. The container name "/legeni_website" is already in use` ; build #4 (ligne remise) → **SUCCESS**
- Build #7 : `Job build, URL http://localhost:8080/job/build/7/` (étape 7)
- Défi (`NETTOYER=true`) : 3 anciennes images supprimées, restent `build-4`, `build-5`, `build-6`
- Poll SCM : `Latest remote head revision … already built` → `No changes` (pas de nouveau commit sur le dépôt du professeur, sur lequel on n'a pas le droit de commit). Le Poll SCM a ensuite été décoché comme demandé.

## Réponses aux questions

**Pourquoi un job de CI doit-il pouvoir être relancé N fois avec le même résultat ?** Un job est relancé très souvent (chaque commit, après une panne, pour reconstruire une version). S'il échoue parce qu'il a déjà tourné, un build rouge ne signifie plus « le code est cassé » mais « l'environnement est sale » : la CI perd sa valeur de signal fiable. Le job doit donc nettoyer ce qu'il recrée (`docker rm -f … || true`).

**1. Où se trouve l'espace de travail ? Sur quelle machine l'image est-elle construite ?** Le workspace est dans le conteneur Jenkins, dans le volume `jenkins_home` : `/var/jenkins_home/workspace/build`. L'image est construite par le **démon Docker de la machine hôte** (Ubuntu), que Jenkins pilote via le socket `/var/run/docker.sock` : les images et le conteneur `legeni_website` sont donc sur l'hôte.

**2. Trois inconvénients d'un job configuré uniquement dans l'interface :**
- pas d'**historique** des modifications (qui a changé quoi, quand) ;
- pas de **revue** possible (pas de pull request sur la configuration) ;
- si Jenkins est perdu ou reconstruit, il faut **tout reconfigurer à la main** (sauf sauvegarde de `jenkins_home`).
→ Solution : le *pipeline as code* (`Jenkinsfile` versionné dans Git, TP 3.5).
