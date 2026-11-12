# Présentation des TPs – déroulé de la démonstration

**Durée conseillée :** 20 à 25 minutes. **Principe :** pour chaque TP, on **montre en direct** dans une interface graphique (Jenkins, navigateur, Dashboard Kubernetes) que ça marche, puis on ouvre le `COMMANDES.md` du TP sur GitHub si on vous pose une question.

## Avant la présentation (10 minutes avant)

1. Lancer le script de préparation :
   ```bash
   bash ~/tp-devops-b3/outils/preparer-demo.sh
   ```
   Tout doit être ✅.
2. Ouvrir dans le navigateur, un onglet par lien :
   - Jenkins : http://localhost:8080 (déjà connecté)
   - le dépôt GitHub des TPs : https://github.com/nedstudio237-cmd/p-devops-b3
   - le dépôt de l'application : https://github.com/nedstudio237-cmd/legeni-webapp
   - Docker Hub : https://hub.docker.com/u/nedstudio
3. Dans un terminal à part, lancer le Dashboard Kubernetes (il ouvre un onglet tout seul) :
   ```bash
   minikube dashboard
   ```
4. Garder un terminal ouvert, police agrandie (**Ctrl + +**).

---

## Partie 1 – Jenkins (≈ 12 min)

### TP 3.1 – Jenkins installé, reproductible
- **Montrer** : tableau de bord Jenkins avec tous les jobs.
- **Cliquer** : job `verif-outils` → **Lancer un build** → **Console Output**.
- **Dire** : « Jenkins tourne en conteneur, il pilote le Docker de la machine, et il a kubectl et Ansible. » Montrer la ligne `groups=…,984` (accès Docker sans `chmod 666`).

### TP 3.2 – Job freestyle `build`
- **Cliquer** : job `build` → **Lancer un build avec des paramètres** → laisser les valeurs → **Build**.
- **Montrer** pendant le build : **Console Output** (`git checkout`, `docker build`, `docker run`).
- **Ouvrir** http://localhost:8092 : le site restaurant s'affiche.
- **Montrer** : **Espace de travail** (code cloné + Dockerfile généré), et la liste des builds où le #3 est rouge (idempotence).

### TP 3.3 – Test d'acceptance (porte de qualité)
- **Cliquer** : job `test-acceptance` → **Lancer un build avec des paramètres** → **Build**.
- **Montrer** dans la console : `Status code 200`, `✅ titre OK`, `✅ 404 OK`, `Temps moyen`.
- **Montrer** l'historique : build #2 rouge (`Response doesn't contain expected content 'Pizzeria'`) = la porte de qualité a bloqué.

### TP 3.4 – Publication sur Docker Hub
- **Cliquer** : job `artefact` → **Build** (≈ 1 min).
- **Montrer** dans la console : Trivy `CRITICAL: 0`, `Login Succeeded`, le jeton affiché `****`, `Image publiée : nedstudio/restaurant:1.0.N-xxxxxxx`.
- **Montrer** : le job `deploy` démarre **tout seul** après → ouvrir http://localhost:8099.
- **Montrer** l'onglet Docker Hub : `nedstudio/restaurant` avec le nouveau tag.
- **Montrer** le build #1 rouge : Trivy a bloqué la publication (3 vulnérabilités critiques).

### TP 3.5 – Pipeline as code (Jenkinsfile)
- **Montrer** sur GitHub : le fichier `Jenkinsfile` du dépôt `legeni-webapp`.
- **Cliquer** : job `legeni-webapp` → **Build with Parameters** → **Build**.
- **Montrer** la vue des stages (**Stage View** ou **Pipeline Overview**) : Tests → Build → Acceptance → Push, tous verts.
- **Montrer** le build #3 : `Tests unitaires` rouge, les stages suivants sautés, rien n'a été publié.

### TP 3.6 – Multibranch et pull requests
- **Cliquer** : job `legeni-webapp-mb` : un sous-job par branche (`main`, `feature/couleur`…).
- **Montrer** sur `feature/couleur` : le stage **Push Docker Hub** gris (sauté) → seule `main` publie.
- **Montrer** sur GitHub : la **PR #1** (coche verte de Jenkins, fusionnée) et la **PR #2** (croix rouge, fusion impossible : `main` protégée).

### TP 3.7 – Qualité et tests en parallèle
- **Cliquer** : job `legeni-qualite` → **Lancer un build** (≈ 1 min 30).
- **Montrer** la vue graphique : les 4 contrôles (tests, lint Python, lint Dockerfile, secrets) **en parallèle**.
- **Montrer** sur la page du build : **Test Result** (6 tests), **Coverage Report** (83 %), **Flake8 Warnings** (0), et les courbes de tendance sur la page du job.
- **Montrer** l'historique : builds #2 à #6 rouges = chaque quality gate déclenchée volontairement.

---

## Partie 2 – Kubernetes (≈ 10 min)

Garder l'onglet **Dashboard Kubernetes** ouvert, namespace `legeni-dev` (menu en haut à gauche).

### TP 4.1 – Le cluster
- **Terminal** : `kubectl get nodes -o wide` puis `kubectl get pods -n kube-system`.
- **Dire** : « le plan de contrôle (API server, etcd, scheduler…) tourne lui-même dans des Pods. »

### TP 4.2 / 4.3 – Pod, Deployment, auto-réparation
- **Dashboard** → **Deployments** → `webapp` : 4 Pods.
- **Terminal** : `kubectl -n legeni-dev delete pod -l app=webapp --wait=false`
- **Montrer** dans le Dashboard (onglet **Pods**) : les Pods sont recréés **tout seuls** en quelques secondes.

### TP 4.4 / 4.7 – L'application, sa configuration, Redis
- **Ouvrir** l'URL de la webapp (affichée par le script) : rafraîchir plusieurs fois → le **hostname change**, le **compteur de visites** augmente (partagé grâce à Redis).
- **Dashboard** → **Config and Storage** → **Config Maps** → `webapp-config` ; **Secrets** → `redis-secret` (valeur masquée).

### TP 4.8 – Mise à jour sans coupure et retour arrière
- **Terminal** (une boucle dans un 2e terminal) :
  ```bash
  URL=$(minikube service webapp -n legeni-dev --url)
  while true; do curl -s -m1 $URL/api/info | grep -o '"version":"[^"]*"'; sleep 0.5; done
  ```
- **Terminal 1** :
  ```bash
  kubectl -n legeni-dev set image deployment/webapp webapp=nedstudio/legeni-webapp:1.0.0
  ```
  La boucle passe de `2.0.0` à `1.0.0` **sans interruption** ; le Dashboard montre les Pods remplacés un par un.
- `kubectl -n legeni-dev rollout undo deployment/webapp` : retour à la version précédente.

### TP 4.5 / 4.6 – (si le temps le permet)
Ces TPs ont été nettoyés après réalisation : montrer leurs **preuves** sur GitHub (`kubernetes/TP4.5_WordPress_MySQL/preuves/04_persistance.txt` : l'article survit à la perte du Pod MySQL ; `TP4.6…/preuves/04_cronjob_sante.txt` : le contrôle planifié détecte la panne).

---

## Conclusion (1 min)
- Ouvrir le dépôt https://github.com/nedstudio237-cmd/p-devops-b3 : le README liste tous les TPs ; chaque dossier contient les fichiers, les commandes avec leur rôle (« 🧠 À mémoriser ») et les preuves.
- Message clé : **tout est décrit dans des fichiers versionnés** (Dockerfile, Jenkinsfile, YAML Kubernetes) → reproductible, relu, traçable.

## Si quelque chose ne marche pas pendant la démo
| Problème | Solution rapide |
|---|---|
| Jenkins ne répond pas | `cd ~/devops-tp && docker compose up -d`, attendre 1 min |
| `kubectl` : connection refused | `minikube start` puis relancer Jenkins (`docker compose up -d`) |
| Un build est long (réseau lent) | montrer un build précédent déjà vert dans l'historique |
| Le site 8092 / 8099 ne s'affiche pas | relancer le job `build` / `artefact` |
