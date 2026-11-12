# TP 4.7 – Namespaces, ConfigMaps et Secrets

**Objectif :** déployer l'application fil rouge (web + Redis) dans un namespace dédié, en **sortant la configuration du code** (ConfigMap) et en protégeant les données sensibles (Secret).

**Statut :** ✅ réalisé et vérifié (défis compris) – preuves dans [`preuves/`](preuves/)

## 🧠 À mémoriser

| Commande | À quoi elle sert |
|---|---|
| `kubectl apply -f .` | applique tous les manifestes du dossier |
| `kubectl get all` | vue d'ensemble du namespace |
| `kubectl create secret generic <nom> --from-literal=CLÉ=valeur` | crée un Secret |
| `envFrom: configMapRef / secretRef` | injecte toutes les clés d'une ConfigMap / d'un Secret en variables d'environnement |
| `kubectl exec deploy/<nom> -- env` | variables reçues par le conteneur |
| `kubectl edit configmap <nom>` | modifie la configuration |
| `kubectl rollout restart deployment <nom>` | recrée les Pods pour relire la configuration |
| `kubectl get all -l env=dev` | sélectionne toutes les ressources d'un environnement |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`00-namespace.yaml`](00-namespace.yaml) | Namespace `legeni-dev` (label `env: dev`) |
| [`10-configmap.yaml`](10-configmap.yaml) | ConfigMap `webapp-config` : `APP_ENV`, `APP_COLOR`, `REDIS_HOST`, `REDIS_PORT` |
| [`20-redis.yaml`](20-redis.yaml) | Redis avec mot de passe (`--requirepass` depuis le Secret) + Service ClusterIP |
| [`30-webapp.yaml`](30-webapp.yaml) | Webapp 2 réplicas (`nedstudio/legeni-webapp:1.0.2`), `envFrom` ConfigMap + Secret, NodePort 30080 |
| [`redis-secret.yaml.exemple`](redis-secret.yaml.exemple) | Défi 3 : Secret en YAML (`stringData`) avec valeur fictive ; le vrai fichier est dans `.gitignore` |

Les labels `env: dev` (défi 2) sont ajoutés sur toutes les ressources et dans les templates de Pods.

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `kubectl apply -f 00-namespace.yaml` | Crée le namespace |
| `kubectl config set-context --current --namespace=legeni-dev` | Namespace par défaut de kubectl |
| `kubectl create secret generic redis-secret -n legeni-dev --from-literal=REDIS_PASSWORD='…'` | Crée le Secret hors Git |
| `kubectl get secret redis-secret -o yaml` | Montre le Secret (valeur en base64) |
| `kubectl get secret redis-secret -o jsonpath='{.data.REDIS_PASSWORD}' \| base64 -d` | Décode la valeur : base64 ≠ chiffrement |
| `kubectl apply -f .` | Applique tous les fichiers du dossier |
| `kubectl get all` | Pods, Services, Deployments, ReplicaSets du namespace |
| `kubectl exec deploy/webapp -- env \| grep -E 'APP_\|REDIS'` | Variables reçues par le conteneur |
| `minikube service webapp -n legeni-dev --url` | URL de l'application |
| `kubectl run dnstest --rm -i --image=busybox:1.36 --restart=Never -- nslookup redis` | Test DNS interne (nom court et complet) |
| `kubectl edit configmap webapp-config` (ici `kubectl patch configmap … -p '{"data":{"APP_COLOR":"#d1242f"}}'`) | Modifie la configuration |
| `kubectl rollout restart deployment webapp` | Recrée les Pods pour qu'ils relisent la configuration |
| `kubectl rollout status deployment webapp` | Attend la fin du redémarrage |
| `curl -s -w ' HTTP %{http_code}' $URL/ready` / `$URL/health` | Défi 1 : readiness (dépendances) vs liveness (processus) |
| `kubectl get all -l env=dev` | Défi 2 : sélectionne toutes les ressources de l'environnement |

## Résultats obtenus
- `kubectl get all` : 2 Pods `webapp` + 1 Pod `redis` **Running**, Services `redis` (ClusterIP) et `webapp` (NodePort 30080).
- Variables : `APP_ENV=dev`, `APP_COLOR=#1f6feb`, `REDIS_HOST=redis`, `REDIS_PORT=6379`, `REDIS_PASSWORD=<masqué>`.
- **Compteur partagé** : 8 rechargements → visites 1, 2, 3 … 8 alors que les 2 Pods répondent tour à tour (`stockage = redis`).
- DNS : `redis` → `redis.legeni-dev.svc.cluster.local` → `10.104.190.107`.
- ConfigMap modifiée : variable **inchangée** dans le Pod (`#1f6feb`) jusqu'au `rollout restart`, puis `#d1242f` (bannière rouge), **sans reconstruire l'image**.
- Défi 1 : sans `secretRef`, `/ready` → **503**, `/health` → **200** ; secret remis → `/ready` 200.
- Défi 2 : `kubectl get all -l env=dev` liste Pods, Services, Deployments, ReplicaSets ; `kubectl get configmap -l env=dev` → `webapp-config`.
- Remarque : ici `REDIS_PORT=6379` est défini explicitement par la ConfigMap, ce qui l'emporte sur la variable `REDIS_PORT=tcp://…` injectée par le Service (le piège rencontré au TP 4.6 ne se produit donc pas).

## Réponses aux questions

**base64, est-ce du chiffrement ? Qui peut lire ce secret ?** Non : base64 est un simple **encodage**, réversible par n'importe qui (`base64 -d`). Le Secret peut être lu par toute personne ou tout compte de service ayant le droit `get secrets` dans le namespace (RBAC), par les Pods qui le montent, et par qui accède à etcd (non chiffré par défaut au repos). Sa protection repose sur les **droits d'accès**, pas sur l'encodage.

**Pourquoi la modification de la ConfigMap n'est-elle pas prise en compte sans redémarrage ?** Les variables d'environnement (`envFrom`) sont injectées **une seule fois, au démarrage du conteneur**. Changer la ConfigMap ne modifie pas l'environnement d'un processus déjà lancé : il faut recréer les Pods (`rollout restart`). (Une ConfigMap montée en **volume** est, elle, mise à jour dans le fichier au bout de quelques secondes, mais l'application doit relire le fichier.)

**Défi 1 : pourquoi `/ready` → 503 mais `/health` → 200 ?** Sans le Secret, l'application n'a pas `REDIS_PASSWORD` : Redis refuse ses commandes (`NOAUTH Authentication required`), donc `/ready` (« mes dépendances fonctionnent ») échoue. `/health` ne vérifie que le processus lui-même (« je suis vivant »), qui tourne toujours. C'est la différence entre readiness et liveness (TP 4.9).

**Défi 3 : pourquoi ne pas commiter `redis-secret.yaml` ? Quelles solutions ?** `stringData` est en clair, et `data` n'est que du base64 : quiconque lit le dépôt (et tout son historique) lit le mot de passe. Solutions : **Ansible Vault** (fichier chiffré dans Git, déchiffré au déploiement, TP 5.5), **Sealed Secrets** (Secret chiffré avec la clé publique du cluster, seul le contrôleur peut le déchiffrer), **External Secrets Operator** (le Secret est lu dans un coffre externe : Vault, AWS/GCP Secret Manager…), ou création hors Git par le pipeline (`kubectl create secret` avec des credentials Jenkins).
