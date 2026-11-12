# TP 3.5 – Projet Jenkinsfile : le pipeline as code

**Objectif :** remplacer les jobs freestyle (configurés à la souris) par un **`Jenkinsfile` stocké dans Git** qui enchaîne : tests unitaires → build de l'image → test d'acceptance → push Docker Hub.

**Statut :** ✅ réalisé et vérifié – preuves dans [`preuves/`](preuves/)
**Dépôt de l'application :** [nedstudio237-cmd/legeni-webapp](https://github.com/nedstudio237-cmd/legeni-webapp) – **image :** [`nedstudio/legeni-webapp`](https://hub.docker.com/r/nedstudio/legeni-webapp)

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`Jenkinsfile`](Jenkinsfile) | Pipeline déclaratif (copie de celui du dépôt `legeni-webapp`) : `DOCKERHUB_ID=nedstudio` + défi `APP_COLOR` |
| [`job-legeni-webapp.xml`](job-legeni-webapp.xml) | Job Jenkins *Pipeline script from SCM* (Git, `*/main`, `Jenkinsfile`, Poll SCM `H/2 * * * *`) |

## Commandes et rôle

### Git (dépôt de l'application)
| Commande | Rôle |
|---|---|
| `cp -r app-fil-rouge ~/legeni-webapp && cd ~/legeni-webapp` | Copie l'application fil rouge dans un nouveau dossier |
| `git init -b main && git add . && git commit -m "…"` | Crée le dépôt local et le premier commit |
| `git remote add origin https://github.com/<id>/legeni-webapp.git` | Relie le dépôt local au dépôt GitHub |
| `git push -u origin main` | Publie sur GitHub (et suit la branche distante) |
| `git commit -am "…" && git push` | Pousse une modification (déclenche le pipeline via Poll SCM) |
| `git revert --no-edit HEAD && git push` | Annule le dernier commit par un nouveau commit (historique conservé) |

### Dans le Jenkinsfile
| Élément / commande | Rôle |
|---|---|
| `pipeline { agent any … }` | Pipeline déclaratif exécuté sur n'importe quel agent (ici le nœud Jenkins) |
| `parameters { string… booleanParam… choice… }` | Paramètres du build (`DOCKERHUB_ID`, `PUSH`, `APP_COLOR`) |
| `environment { IMAGE … VERSION = "1.0.${env.BUILD_NUMBER}" … }` | Variables communes à tous les stages (nom d'image, version unique) |
| `options { timestamps(); timeout(…); buildDiscarder(…) }` | Horodatage de la console, durée max 20 min, garder 10 builds |
| `docker build --target test -t legeni-webapp:test .` | Stage **Tests unitaires** : l'étape `test` du Dockerfile lance `flake8` + `pytest` |
| `docker build --build-arg APP_VERSION=$VERSION -t $IMAGE:$VERSION -t $IMAGE:latest .` | Stage **Build image** : image finale avec la version |
| `docker network create $CI_NETWORK` | Réseau Docker dédié au test de ce build |
| `docker run -d --name $TEST_CONTAINER --network $CI_NETWORK -e APP_COLOR=… $IMAGE:$VERSION` | Lance l'application à tester |
| `docker run --rm --network $CI_NETWORK curlimages/curl:8.11.1 -sf --retry 10 … /health` | Attend que l'application réponde (conteneur curl sur le même réseau) |
| `… curl … http://$TEST_CONTAINER:5000/ \| grep -q "Version $VERSION"` (+ `$APP_COLOR`) | Vérifie la version (et la couleur, défi) dans la page |
| `when { expression { params.PUSH } }` | N'exécute le stage Push que si `PUSH` est coché |
| `withCredentials([usernamePassword(credentialsId: 'dockerhub', …)])` | Injecte le credential Docker Hub (masqué dans les logs) |
| `docker login … --password-stdin` / `docker push $IMAGE:$VERSION` / `…:latest` | Publication sur Docker Hub |
| `post { always { docker rm -f …; docker network rm … } }` | Nettoyage **toujours** exécuté, même en cas d'échec |

### Dans Jenkins
| Action | Rôle |
|---|---|
| **Nouvel item → Pipeline → Pipeline script from SCM** | Le job lit son pipeline dans le dépôt Git (`Jenkinsfile`) |
| **Lancer un build** (1er) | Jenkins découvre les paramètres définis dans le Jenkinsfile |
| **Build with Parameters** | Lance le pipeline avec les valeurs choisies |
| **Stage View / Pipeline Graph** | Vue de chaque stage et de son statut |
| **Poll SCM** `H/2 * * * *` | Lance le pipeline dans les 2 min après un push |

## Résultats obtenus
- Build #1 : 4 stages verts, image `nedstudio/legeni-webapp:1.0.1` publiée (paramètres pas encore connus → couleur vide).
- Build #2 (paramètres, `APP_COLOR=#2da44e`) : `✅ version 1.0.2 et couleur #2da44e présentes dans la page`, push `1.0.2` + `latest`.
- Build #3 (**Started by an SCM change**, `status="ko"`) : stage **Tests unitaires** rouge (`AssertionError: assert {'status': 'ko'} == {'status': 'ok'}`, `1 failed, 5 passed`), stages suivants *skipped*, **aucune image publiée**.
- Build #4 (**Started by an SCM change**, après `git revert`) : retour au vert, `1.0.4` publiée.
- Tags Docker Hub : `1.0.1 1.0.2 1.0.4 latest` (pas de `1.0.3`). Aucun jeton en clair dans les consoles.

## Réponses aux questions

**À quoi servent `parameters`, `environment`, `options`, `post` ?**
- `parameters` : valeurs saisies au lancement (« Build with Parameters »), accessibles via `params.X` et comme variables d'environnement dans `sh`.
- `environment` : variables définies une fois pour tout le pipeline (nom d'image, version, noms du conteneur et du réseau de test).
- `options` : comportement du job (horodatage, timeout global, rotation des anciens builds).
- `post` : actions après les stages, selon le résultat (`always`, `success`, `failure`) — ici le nettoyage garanti.

**Pourquoi un conteneur `curlimages/curl` sur un réseau dédié plutôt que `curl http://localhost:5000` ?** Jenkins tourne **dans un conteneur** : son `localhost` est lui-même, pas l'application. L'application est un autre conteneur lancé sur le Docker de l'hôte. Un conteneur `curl` placé sur le **même réseau Docker** que l'application la joint par son nom (`webapp-ci-N:5000`). Le réseau dédié à chaque build isole aussi les builds entre eux.

**Que se passe-t-il pour les étapes suivantes si `Tests unitaires` échoue ?** Elles sont **sautées** (« skipped due to earlier failure ») : aucune image construite, testée ni poussée. Seul le bloc `post` s'exécute (nettoyage + message d'échec). Constaté au build #3.
