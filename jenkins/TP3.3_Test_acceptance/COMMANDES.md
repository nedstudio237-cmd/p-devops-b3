# TP 3.3 – Projet test-acceptance : vérifier automatiquement que l'application répond

**Objectif :** après la construction de l'image, la lancer dans un conteneur de **test** et vérifier par HTTP que le site répond **et** affiche le bon contenu. Si le test échoue, le build est rouge : c'est la **porte de qualité** (*quality gate*).

**Statut :** ✅ réalisé et vérifié – preuves dans [`preuves/`](preuves/)

## Fichiers réalisés

| Fichier | Étape du job |
|---|---|
| [`job-test-acceptance.xml`](job-test-acceptance.xml) | Configuration complète du job `test-acceptance` (copie de `build`) |
| [`etape1_build_run_test.sh`](etape1_build_run_test.sh) | 1. build de l'image + conteneur de test sur le réseau de Jenkins |
| *(plugin HTTP Request)* | 2. GET `http://${IMAGE_NAME}-test/` : code 200 + contenu `Restaurant` |
| [`etape3_verif_curl.sh`](etape3_verif_curl.sh) | 3. vérifications sans plugin : titre, image statique, 404 |
| [`etape4_defi_performance.sh`](etape4_defi_performance.sh) | 4. défi : temps de réponse moyen < 500 ms |
| [`etape5_nettoyage.sh`](etape5_nettoyage.sh) | 5. suppression du conteneur de test |

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .` | Construit l'image à tester |
| `docker inspect jenkins -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}'` | Trouve le réseau Docker de Jenkins (ici `minikube`) |
| `docker run -d --name ${TEST} --network ${JENKINS_NET} …` | Lance le conteneur de test **sur le réseau de Jenkins** pour le joindre par son nom |
| `for i in $(seq 1 10); do curl -sf http://${TEST}/ && break; sleep 1; done` | Attend que nginx soit prêt (10 s max) |
| **HTTP Request** (plugin) : URL, `GET`, codes `200`, contenu `Restaurant` | Test d'acceptance « sans code » : échoue si le code ou le contenu ne correspond pas |
| `curl -sf http://${TEST}/ \| grep -qi "<title>Restaurant"` | Vérifie le titre de la page |
| `curl -sf -o /dev/null -w "%{http_code} %{content_type}\n" http://${TEST}/1.jpg` | Vérifie qu'une ressource statique est servie (`200 image/jpeg`) |
| `test "$(curl -s -o /dev/null -w '%{http_code}' …/nexiste-pas)" = "404"` | Vérifie qu'une page inexistante renvoie 404 |
| `curl -s -o /dev/null -w '%{time_total}'` (x10) + `awk` | Défi : mesure le temps moyen de réponse et échoue au-delà de 0,5 s |
| `docker rm -f ${IMAGE_NAME}-test` | Nettoie le conteneur de test |
| `docker ps -a --filter name=restaurant-test` | Vérifie qu'il ne reste pas de conteneur de test |

## Résultats obtenus
- Build #1 → **SUCCESS** : `Status code 200 is in the accepted range: 200`, `✅ titre OK`, `200 image/jpeg`, `✅ 404 OK`, temps moyen 0,004 s ; plus de conteneur `restaurant-test` après le build.
- Build #2 (porte cassée) → **FAILURE** : `Fail: Response doesn't contain expected content 'Pizzeria'`. L'image a été construite mais rien n'est allé plus loin.
  *Adaptation : le TP demande de changer le `<title>` sur GitHub ; sans droit de commit sur le dépôt du professeur, on a changé le contenu attendu (`Pizzeria`) : même effet, la page ne correspond plus à l'attendu.*
- Après l'échec, `restaurant-test` **est resté** (l'étape de nettoyage n'a pas été exécutée).
- Build #3 (contenu attendu remis à `Restaurant`) → **SUCCESS**.

## Réponses aux questions

**Pourquoi `curl http://localhost/` ne fonctionnerait-il pas ?** Le script s'exécute **dans le conteneur Jenkins** : `localhost` y désigne Jenkins lui-même, pas le conteneur de test. Le conteneur de test est un autre conteneur (lancé sur le Docker de l'hôte) : on le joint par **son nom** sur un réseau Docker commun.

**Si l'étape HTTP Request échoue, la dernière étape (nettoyage) est-elle exécutée ?** Non : un job freestyle s'arrête à la première étape en échec. Le conteneur de test reste donc en place (constaté au build #2). C'est pour cela que l'étape 1 commence par `docker rm -f ${TEST}`, et que le Jenkinsfile (TP 3.5) utilisera `post { always { … } }`.

**1. Test unitaire vs test d'acceptance ?** Le **test unitaire** vérifie une petite partie du code isolément (une fonction), sans déployer, en quelques secondes. Le **test d'acceptance** vérifie l'application **complète, déployée**, du point de vue de l'utilisateur (HTTP). Les tests unitaires passent **en premier** : rapides et peu coûteux, ils évitent de construire et lancer une image dont le code est déjà cassé.

**2. Plugin HTTP Request ou `curl` ?**
- Plugin : configuration simple sans écrire de code, messages clairs dans la console ; mais dépend d'un plugin, limité à ce qu'il propose, configuration cliquée non versionnée.
- `curl` : portable (fonctionne partout, y compris dans un Jenkinsfile ou un autre outil de CI), très souple (combinaisons avec `grep`, `awk`…) ; mais il faut écrire et maintenir le script.
