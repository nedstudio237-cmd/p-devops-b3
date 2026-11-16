# TP 3.8 – Déploiement continu : staging automatique, production validée, rollback

**Objectif :** prolonger la CI par la **CD** : chaque build de `main` est déployé automatiquement en *staging* (port 8081) ; la mise en *production* (port 8082) attend une **validation humaine**, est vérifiée par un *smoke test* et revient **automatiquement** à la version précédente en cas d'échec.

**Statut :** ✅ étapes 1 à 6 réalisées et vérifiées ; étape 7 (e-mail) : pipeline prêt, envoi Gmail à activer avec [`../../outils/configurer-email.sh`](../../outils/configurer-email.sh) (nécessite le mot de passe d'application Gmail) – preuves dans [`preuves/`](preuves/)
**Dépôt :** [`legeni-webapp`](https://github.com/nedstudio237-cmd/legeni-webapp) – `main` est protégée (TP 3.6) : chaque modification passe par une **pull request** (#3 à #6), construite par Jenkins avant la fusion.

## 🧠 À mémoriser

| Commande / notion | À quoi ça sert |
|---|---|
| `input message: '…', ok: 'Déployer'` | met le pipeline en **pause** jusqu'à la validation d'un humain |
| `timeout(time: 15, unit: 'MINUTES') { input … }` | abandonne si personne ne valide (le pipeline ne bloque pas Jenkins indéfiniment) |
| `when { branch 'main' }` | seule `main` va en production ; les autres branches s'arrêtent au staging |
| `credentials('redis-password-prod')` | injecte un secret Jenkins dans une variable (masqué dans les logs) |
| `docker compose -p legeni-prod up -d --wait` | déploie une stack nommée et attend qu'elle soit *healthy* |
| `./deploy/smoke-test.sh <projet> <version>` | test de fumée : l'appli répond-elle, avec la bonne version ? |
| `try { … } catch (err) { …rollback… ; error "…" }` | rollback automatique puis build **rouge** |
| `disableConcurrentBuilds()` | jamais deux builds du même job en même temps |
| `emailext to: …, subject: …, body: …` | notification e-mail dans `post { failure { … } }` |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`Jenkinsfile`](Jenkinsfile) | Pipeline CI + CD final (copie de `main`) : tests, build, staging + smoke test, validation, prod + smoke test + rollback, `emailext` en cas d'échec |
| [`smoke-test.sh`](smoke-test.sh) | Test de fumée (conteneur `curl` sur le réseau du projet Compose) |
| [`../../outils/configurer-email.sh`](../../outils/configurer-email.sh) | Étape 7 : crée le credential `gmail-smtp`, configure *Extended E-mail Notification* (smtp.gmail.com:465, SSL), provoque un échec et supprime la branche de test |

Credentials Jenkins créés : `redis-password-staging`, `redis-password-prod` (Secret text, `openssl rand -hex 16`).

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `cat deploy/smoke-test.sh` | lecture du test de fumée |
| `openssl rand -hex 16` | génère les mots de passe Redis (staging / prod) |
| `git push origin cd` + pull request → `main` | le Jenkinsfile CD arrive sur `main` via une PR (branche protégée) |
| *Stage View* → **Déployer** (ici : `POST …/input/<id>/proceedEmpty`, même action que le bouton) | validation humaine de la mise en production |
| `curl -s localhost:8081/api/info` / `:8082` | version et environnement de staging / prod |
| `git push origin feature/panne-prod` | une branche : staging seulement, prod *skipped* |
| `[ "$PROJECT" = legeni-prod ] && { echo "panne simulée"; exit 1; }` | panne simulée **en prod uniquement** |
| `docker ps --filter name=legeni-prod --format "{{.Names}} {{.Image}}"` | image en prod après le rollback |
| boucle `curl localhost:8082/api/info` toutes les 0,3 s | mesure la disponibilité de la prod pendant le rollback |
| `./outils/configurer-email.sh` | étape 7 : configuration SMTP Gmail + échec volontaire → e-mail |

## Résultats obtenus
- **Branche `cd`** (avant fusion) : tests, build, staging OK ; *Validation production* et *Déploiement production* **skipped** (preuve `01`).
- **PR #3 fusionnée → `main` #3** : staging 1.0.3 (`env: staging`, bannière orange `#bf8700`) ; pipeline en pause : `Déployer la version 1.0.3 en production ?` ; après validation : `Approved by …`, `Version en production avant déploiement : none`, `✅ legeni-prod répond en version 1.0.3` → prod 1.0.3 (`env: prod`, vert) (preuves `04a`–`04d`).
- **Étape 5** : branche `feature/panne-prod` → `Stage "Validation production" skipped due to when conditional` (preuve `05`).
- **Étape 6 (PR #4 → `main` #4)** : `Version en production avant déploiement : legeni-webapp:1.0.3` → `panne simulée` → `Smoke test KO : retour à legeni-webapp:1.0.3` → `ERROR: Déploiement production échoué, rollback effectué`, build **FAILURE** ; `docker ps` : `legeni-prod-web-1 legeni-webapp:1.0.3` (preuves `06a`, `06c`).
- **Disponibilité pendant le rollback** (200 requêtes, preuve `06b`) : 1.0.3 → **1.0.4 pendant ~5 s** → retour 1.0.3 ; **13 erreurs** en deux coupures d'environ 2 s, au moment où Compose **recrée** le conteneur (arrêt de l'ancien, démarrage du nouveau). La prod n'a jamais été coupée longtemps, mais ce n'est pas du *zero downtime* : il faudrait plusieurs réplicas derrière un répartiteur (Kubernetes, TP 4.8).
- Panne annulée (PR #5), puis notification e-mail activée (PR #6) : `main` #5 et #6 **verts**, prod en **1.0.6**.
- **Incident observé** : la branche `fix/annuler-panne` et sa PR-5 ont été construites **en même temps** et ont déployé le **même** staging : `Conflict. The container name "/…_legeni-staging-web-1" is already in use` (preuve `06d`). Relancé seul → OK.

## Réponses aux questions

**1. Livraison continue ou déploiement continu ?** *Livraison continue* (continuous delivery) : chaque version est **prête** à partir en production, mais la mise en prod attend une décision humaine. *Déploiement continu* (continuous deployment) : tout build vert part en production **sans intervention**. Ce pipeline implémente la **livraison continue** (étape `input`). Pour passer au déploiement continu, il suffit de **retirer le stage *Validation production*** (l'`input`) : le smoke test et le rollback automatique deviennent alors le seul filet de sécurité.

**2. Pourquoi `disableConcurrentBuilds()` ?** Deux builds du même job en parallèle pourraient déployer en même temps sur le même environnement (conteneurs remplacés deux fois, versions mélangées), et le rollback pourrait relire une « version précédente » qui est en fait celle de l'autre build. Limite constatée dans ce TP : l'option ne vaut **que pour un job** ; dans un multibranch, chaque branche/PR est un job différent, d'où le conflit sur le staging partagé (preuve `06d`). Solution : `lock(resource: 'staging') { … }` (plugin *Lockable Resources*) ou un staging par branche.

**3. Quelles données ne seraient pas restaurées ?** Le rollback ne remet que l'**image** (le code). Les **données** de Redis/de la base restent dans l'état laissé par la nouvelle version : migrations de schéma (colonnes ajoutées/supprimées, tables renommées), données converties dans un nouveau format, données écrites pendant que la nouvelle version tournait. L'ancienne version pourrait ne plus savoir les lire. Il faut donc des migrations **rétrocompatibles** (*expand/contract*), des scripts de migration inverse, et une **sauvegarde avant déploiement** (comme le défi du TP 5.5).
