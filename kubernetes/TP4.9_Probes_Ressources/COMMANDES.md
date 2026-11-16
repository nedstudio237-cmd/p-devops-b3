# TP 4.9 – Sondes de santé (probes) et gestion des ressources

**Objectif :** permettre à Kubernetes de savoir **quand un Pod est vivant** et **quand il peut recevoir du trafic**, et maîtriser la consommation CPU/RAM de chaque conteneur.

**Statut :** ✅ réalisé et vérifié (défi compris) – preuves dans [`preuves/`](preuves/)

## 🧠 À mémoriser

| Commande / champ | À quoi ça sert |
|---|---|
| `readinessProbe` | « prêt à servir ? » – en échec, le Pod est **retiré du Service** (pas redémarré) |
| `livenessProbe` | « encore vivant ? » – en échec, le conteneur est **redémarré** |
| `resources: requests / limits` | réservation (pour le placement) / plafond (CPU ralenti, mémoire → `OOMKilled`) |
| `kubectl describe pod <pod> \| grep -E 'Liveness\|Readiness'` | affiche les sondes configurées |
| `kubectl get events --sort-by=.lastTimestamp` | événements récents : `Unhealthy`, `Killing`, `FailedScheduling`, `exceeded quota`… |
| `kubectl top pods` / `kubectl top nodes` | consommation réelle CPU/RAM |
| `kubectl describe node \| grep -A8 "Allocated resources"` | ce qui est déjà réservé sur le nœud |
| `kubectl describe quota` | consommation d'un namespace par rapport à son quota |

| Sonde | Question posée | Si elle échoue |
|---|---|---|
| `startupProbe` | l'application a-t-elle fini de démarrer ? | les autres sondes attendent ; après N échecs → redémarrage |
| `livenessProbe` | le processus est-il bloqué ? | conteneur **redémarré** |
| `readinessProbe` | peut-il servir des requêtes maintenant ? | Pod **retiré du Service** |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`30-webapp.yaml`](30-webapp.yaml) | webapp : `readinessProbe` sur `/ready` (vérifie Redis), `livenessProbe` sur `/health`, requests/limits |
| [`20-redis.yaml`](20-redis.yaml) | Défi : Redis avec readiness `exec` (`redis-cli ping`), liveness `tcpSocket`, requests/limits |
| [`oom.yaml`](oom.yaml) | Pod qui alloue 300 Mo avec une limite de 64 Mo → `OOMKilled` |
| [`50-quota.yaml`](50-quota.yaml) | ResourceQuota du namespace : 10 Pods, 1 CPU et 1 Gi demandés, 2 Gi de limite mémoire |

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `kubectl apply -f 30-webapp.yaml` | ajoute les sondes et les ressources |
| `kubectl scale deployment redis --replicas=0` | simule la panne d'une dépendance |
| `kubectl get pods -l app=webapp -w` | voir `READY 0/1` alors que `RESTARTS` reste à 0 |
| `kubectl describe svc webapp \| grep Endpoints` | le Service n'a plus de Pod prêt vers qui envoyer le trafic |
| `kubectl get endpointslices -l kubernetes.io/service-name=webapp -o jsonpath='{…conditions.ready}'` | état « prêt » de chaque Pod derrière le Service |
| `kubectl patch deployment webapp --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/inexistant"}]'` | modifie un seul champ (ici casse la sonde de liveness) |
| `kubectl rollout undo deployment webapp` | annule la modification |
| `kubectl apply -f oom.yaml` / `kubectl get pod oom` | Pod tué pour dépassement mémoire |
| `kubectl get pod oom -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}'` | raison de l'arrêt (`OOMKilled`, code 137) |
| `kubectl run gros --image=… --overrides='{…"requests":{"cpu":"50"}…}'` | Pod qui demande 50 CPU → impossible à placer |
| `kubectl describe pod gros \| tail -3` | `FailedScheduling … Insufficient cpu` |
| `kubectl apply -f 50-quota.yaml` / `kubectl describe quota quota-dev` | crée et consulte le quota du namespace |
| `kubectl scale deployment webapp --replicas=15` | dépasse volontairement le quota |
| `kubectl delete -f 50-quota.yaml` | supprime le quota |

## Résultats obtenus
- Sondes visibles : `Liveness: http-get :5000/health … period=10s failureThreshold=3`, `Readiness: http-get :5000/ready … period=5s failureThreshold=2`.
- **Redis arrêté** : Pods webapp `0/1 READY`, **`RESTARTS 0`**, Endpoints du Service vides, site inaccessible ; Redis relancé → `1/1`, HTTP 200, **sans intervention**.
- **Liveness cassée** (`/inexistant`) : `RESTARTS` monte (2, 3, 4…) toutes les ~30 s ; événement `Container webapp failed liveness probe, will be restarted` ; `rollout undo` → retour à la normale.
- **Observation réelle** : juste après un démarrage, les Pods sains avaient aussi des échecs ponctuels de sonde (`context deadline exceeded`, délai 1 s) : le conteneur consommait **202m de CPU pour une limite de 200m** → ralenti (*throttling*) pendant le démarrage de gunicorn. Grâce à `failureThreshold: 3`, aucun redémarrage. En production on augmenterait `timeoutSeconds` ou on ajouterait une `startupProbe`.
- Nœud : requests 1150m CPU (28 %) / 638 Mi.
- `oom` → **`OOMKilled`** (code 137) ; `gros` → **`Pending`**, `0/1 nodes are available: 1 Insufficient cpu`.
- **Quota** : `webapp` bloqué à `6/15` (puis 9 Pods + Redis = 10), événement `exceeded quota: quota-dev, requested: pods=1, used: pods=10, limited: pods=10`.
- **Défi Redis** : sondes `exec` et `tcp-socket`, requests 50m/32Mi, limits 200m/128Mi ; webapp `/ready` → 200. Quota ensuite supprimé.

## Réponses aux questions

**Pourquoi ne pas vérifier Redis dans la `livenessProbe` ?** Si Redis tombe, tous les Pods webapp échoueraient leur liveness et seraient **redémarrés en boucle**, alors qu'ils ne sont pas en cause : redémarrer l'application ne répare pas Redis, ça ajoute juste de la charge et des coupures (effet domino). Une dépendance indisponible doit seulement rendre le Pod **non prêt** (readiness) : il sort du Service, et y revient tout seul quand Redis revient.

**requests vs limits ?** `requests` = ce que le scheduler **réserve** pour placer le Pod (un nœud sans assez de ressources libres → `Pending`). `limits` = **plafond** : au-delà du CPU le conteneur est ralenti, au-delà de la mémoire il est tué (`OOMKilled`).

**Quota** : dès qu'un ResourceQuota porte sur `requests.cpu` / `limits.memory`, **tout nouveau Pod sans `resources` est refusé** dans le namespace, d'où l'intérêt de donner des ressources à Redis (défi).
