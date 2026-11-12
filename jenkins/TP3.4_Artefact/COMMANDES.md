# TP 3.4 – Projet Artefact : publier l'image testée sur Docker Hub

**Objectif :** compléter la chaîne *build → test → publication* : l'image qui a passé le test d'acceptance reçoit un **tag unique et traçable** et est **poussée sur Docker Hub**, avec des identifiants stockés dans les **credentials** Jenkins. Puis enchaîner un job `deploy`.

**Statut :** ✅ réalisé et vérifié – preuves dans [`preuves/`](preuves/)
**Image publiée :** [`nedstudio/restaurant`](https://hub.docker.com/r/nedstudio/restaurant) – tags `1.0.2-1a25da7` et `latest`

## 🧠 À mémoriser

| Commande | À quoi elle sert |
|---|---|
| `Credentials → Username with password (ID dockerhub)` | stocke identifiant + jeton dans Jenkins, jamais dans le job |
| `echo "$TOKEN" \| docker login -u "$USER" --password-stdin` | connexion au registre sans mettre le jeton en argument |
| `docker tag image:1.0.12-abc1234 image:latest` | ajoute un second nom (tag) à une image existante |
| `docker push compte/image:tag` | publie l'image sur Docker Hub |
| `docker build --label org.opencontainers.image.revision=$GIT_COMMIT` | inscrit le commit source dans l'image (traçabilité) |
| `docker inspect image --format '{{index .Config.Labels "…revision"}}'` | retrouve le commit qui a produit l'image |
| `trivy image --severity CRITICAL --ignore-unfixed --exit-code 1 image` | bloque si vulnérabilité critique corrigeable |

## Fichiers réalisés

| Fichier | Rôle |
|---|---|
| [`job-artefact.xml`](job-artefact.xml) | Job `artefact` : paramètres, credentials, 6 étapes, archivage, déclenchement de `deploy` |
| [`etape1_build_test.sh`](etape1_build_test.sh) | Build avec tag unique `1.0.<n>-<sha>` + label du commit, conteneur de test, `tag.txt` |
| *(plugin HTTP Request)* | Test d'acceptance : code 200 + contenu `Restaurant` |
| [`etape2_verif_curl.sh`](etape2_verif_curl.sh) | Vérifications `curl` (titre, image, 404) |
| [`etape3_defi_trivy.sh`](etape3_defi_trivy.sh) | Défi : scan Trivy, échec si CRITICAL corrigeable |
| [`etape4_publication.sh`](etape4_publication.sh) | `docker login` + `push` du tag unique et de `latest` |
| [`etape5_nettoyage.sh`](etape5_nettoyage.sh) | Supprime le conteneur de test |
| [`job-deploy.xml`](job-deploy.xml) / [`deploy.sh`](deploy.sh) | Job `deploy` : relance le site depuis Docker Hub sur le port 8099 |

`__APK_UPGRADE__` dans l'étape 1 est remplacé par `RUN apk upgrade --no-cache` dans le job final (voir défi).

## Commandes et rôle

| Commande / action | Rôle |
|---|---|
| **Credentials** → *Username with password*, ID `dockerhub` | Stocke identifiant + **jeton** Docker Hub dans Jenkins (jamais dans le job ni le code) |
| **Use secret text(s) or file(s)** → `DOCKERHUB_USER` / `DOCKERHUB_TOKEN` | Injecte le credential dans le build sous forme de variables (masquées dans la console) |
| `UNIQUE_TAG=${IMAGE_TAG}.${BUILD_NUMBER}-${GIT_COMMIT:0:7}` | Tag unique par build : version + n° de build + commit |
| `docker build --label org.opencontainers.image.revision=${GIT_COMMIT} -t … .` | Construit l'image et y inscrit le commit source (traçabilité) |
| `echo "${UNIQUE_TAG}" > tag.txt` | Transmet le tag à l'étape de publication et sert d'artefact |
| `echo "${DOCKERHUB_TOKEN}" \| docker login -u "${DOCKERHUB_USER}" --password-stdin` | Connexion à Docker Hub sans mettre le jeton sur la ligne de commande |
| `docker push ${IMAGE}:${UNIQUE_TAG}` | Publie l'image testée |
| `docker tag … ${IMAGE}:latest` + `docker push ${IMAGE}:latest` | `latest` ne pointe que vers une image qui a passé les tests |
| `docker logout` | Supprime la session Docker Hub |
| **Archiver des artefacts** → `tag.txt` | Garde la trace de l'image produite par chaque build |
| **Construire d'autres projets** → `deploy` (si stable) | Enchaîne les jobs : `deploy` démarre après un `artefact` vert |
| `docker run --rm -v /var/run/docker.sock:… aquasec/trivy:0.57.1 image --severity CRITICAL --ignore-unfixed --exit-code 1 <image>` | Défi : scanne l'image, fait échouer le build si vulnérabilité critique corrigeable |
| `RUN apk upgrade --no-cache` (Dockerfile) | Met à jour les paquets Alpine de l'image → corrige les vulnérabilités |
| `docker pull nedstudio/restaurant:latest` + `docker inspect … --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'` | Vérifie quel commit a produit l'image publiée |
| `docker exec jenkins grep -A3 dockerhub /var/jenkins_home/credentials.xml` | Montre comment Jenkins stocke le secret |

## Résultats obtenus
- **Build #1 → FAILURE (défi)** : Trivy trouve `Total: 3 (CRITICAL: 3)` dans `nginx:1.27-alpine` (brotli, libcrypto3, libssl3) → aucune publication.
- **Build #2 → SUCCESS** (après `apk upgrade`) : `Total: 0 (CRITICAL: 0)`, `Login Succeeded`, push de `1.0.2-1a25da7` et `latest`, `tag.txt` archivé, `deploy` #1 déclenché automatiquement → site sur `http://localhost:8099`.
- Le jeton n'apparaît **jamais** en clair dans la console (0 occurrence).
- Traçabilité : label de l'image = `1a25da77c1be…` = commit `main` de GitHub.
- **Build #3 → FAILURE** (contenu attendu `Pizzeria`) : tags Docker Hub identiques avant/après, `deploy` non déclenché.

## Réponses aux questions

**Où Jenkins stocke-t-il le secret, et sous quelle forme ?** Dans `/var/jenkins_home/credentials.xml`, **chiffré** (`<password>{AQAAABAAAA…}</password>`) avec une clé propre à cette instance (`secrets/master.key`, `secrets/hudson.util.Secret`). Il est déchiffré uniquement au moment du build et masqué (`****`) dans les logs.

**1. Pourquoi un tag unique plutôt que toujours `latest` ?** Un tag unique identifie **exactement** une image (et donc un commit) : on sait ce qui tourne, on peut reproduire, comparer et **revenir en arrière** (rollback) vers un tag précis. `latest` est une étiquette mobile : si elle change pendant un redéploiement, des serveurs peuvent tourner avec des versions **différentes** sous le même nom, sans qu'on sache lesquelles, et le rollback devient impossible.

**2. Combien de jobs, d'étapes et d'écrans depuis le TP 3.2 ?** 4 jobs (`build`, `test-acceptance`, `artefact`, `deploy`), environ 15 étapes de build (shell + HTTP Request), plus paramètres, SCM, credentials, archivage et déclencheurs, soit une dizaine d'écrans de configuration. Si Jenkins est perdu sans sauvegarde, il faut de l'ordre d'une heure ou plus pour tout recliquer, avec un fort risque d'erreur → motivation du **pipeline as code** (Jenkinsfile versionné, TP 3.5).
