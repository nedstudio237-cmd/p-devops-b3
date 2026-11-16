# TP 4.10 – Stockage persistant : PV, PVC et StatefulSet

**Objectif :** comprendre comment un Pod (éphémère par nature) conserve ses données, et pourquoi les bases de données se déploient en **StatefulSet**.

**Statut :** ✅ réalisé et vérifié (défi compris) – preuves dans [`preuves/`](preuves/)

## 🧠 À mémoriser

| Commande / notion | À quoi ça sert |
|---|---|
| `kubectl get storageclass` | classes de stockage ; celle marquée `(default)` crée les volumes automatiquement |
| `kubectl get pv,pvc` | volumes (PV) et demandes de volume (PVC) ; `Bound` = demande satisfaite |
| PVC (PersistentVolumeClaim) | **demande** de stockage faite par une application (taille, mode d'accès) |
| PV (PersistentVolume) | **volume réel** (créé à la main ou automatiquement par la StorageClass) |
| `volumeClaimTemplates` (StatefulSet) | crée automatiquement **un PVC par Pod** (`data-redis-0`, `data-redis-1`…) |
| `kubectl get sts` | liste les StatefulSets |
| `kubectl scale sts redis --replicas=3` | ajoute des Pods **dans l'ordre** (`redis-0`, puis `-1`, puis `-2`) |
| `kubectl wait --for=condition=Ready pod/redis-0` | attend qu'un Pod précis soit prêt |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`pv-manuel.yaml`](pv-manuel.yaml) | PV statique `hostPath` 1 Gi (`Retain`, classe `manuel`) + PVC 500 Mi qui s'y lie |
| [`20-redis-statefulset.yaml`](20-redis-statefulset.yaml) | Redis en StatefulSet, persistance AOF (`--appendonly yes`), `volumeClaimTemplates` 1 Gi monté sur `/data` |
| [`defi-wordpress/`](defi-wordpress/) | Défi : MySQL en StatefulSet (+ Service headless) et WordPress avec un PVC `wordpress-html` pour `/var/www/html` |

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `kubectl exec deploy/redis -- sh -c 'redis-cli -a "$REDIS_PASSWORD" get visits'` | lit le compteur dans Redis |
| `kubectl delete pod -l app=redis` | supprime le Pod Redis (sans volume : données perdues) |
| `kubectl apply -f pv-manuel.yaml` | crée un PV à la main et un PVC qui le réclame (provisionnement statique) |
| `kubectl delete pvc pvc-manuel` puis `kubectl get pv` | avec `Retain`, le PV passe en `Released` et garde ses données |
| `kubectl delete deployment redis` | supprime le Deployment Redis (le Service reste) |
| `kubectl apply -f 20-redis-statefulset.yaml` | crée le StatefulSet → Pod `redis-0` + PVC `data-redis-0` |
| `kubectl get sts,pods,pvc -l app=redis` | StatefulSet, Pods et PVC de Redis |
| `kubectl delete pod redis-0` + `kubectl wait --for=condition=Ready pod/redis-0` | supprime le Pod et attend qu'il revienne (même nom, même PVC) |
| `kubectl scale sts redis --replicas=3` / `=1` | création dans l'ordre / suppression dans l'ordre inverse ; les PVC restent |
| `kubectl -n wordpress exec deploy/wordpress -- …` | défi : installe un thème dans `wp-content/themes` (sur le PVC) |
| `kubectl delete pvc data-redis-1 data-redis-2` | supprime à la main les PVC devenus inutiles |

## Résultats obtenus
- **Problème** : compteur à 5, Pod Redis supprimé → `(nil)` : les données étaient dans le conteneur.
- StorageClass `standard (default)`, provisionneur `k8s.io/minikube-hostpath`, politique `Delete`.
- **PV manuel** : PVC `Bound` à `pv-manuel` ; il obtient **1 Gi** (le PV entier) alors qu'il en demandait 500 Mi. PVC supprimé → PV en **`Released`** (`Retain`).
- **StatefulSet** : Pod **`redis-0`**, PVC **`data-redis-0` Bound** (créé automatiquement).
- **Persistance** : compteur **9** → `redis-0` supprimé → revenu → toujours **9**.
- **Identité stable** : `redis-0` → `redis-1` → `redis-2` créés **dans l'ordre**, un PVC chacun ; retour à 1 réplica → les PVC `data-redis-1` et `-2` **restent** (supprimés ensuite à la main).
- **Défi** : `mysql-0` + PVC `data-mysql-0`, WordPress + PVC `wordpress-html` ; thème **Astra 4.14.3** installé → Pod WordPress supprimé → thème **toujours présent** ; `mysql-0` supprimé → revient avec le même nom et le même PVC.

⚠️ **À savoir** : avec 3 réplicas Redis derrière le même Service, chaque Pod a **ses propres** données (ils ne se répliquent pas entre eux) : l'application verrait des compteurs différents. Un StatefulSet donne l'identité et le stockage stables, mais la **réplication** est le travail du logiciel lui-même (Redis Sentinel/Cluster, réplication MySQL…). D'où le retour à 1 réplica.

## Réponses aux questions

**Modes d'accès :**
- `ReadWriteOnce` (RWO) : lecture-écriture par **un seul nœud** à la fois (le cas le plus courant : disque bloc).
- `ReadOnlyMany` (ROX) : lecture seule par **plusieurs nœuds**.
- `ReadWriteMany` (RWX) : lecture-écriture par **plusieurs nœuds** (stockage réseau : NFS, CephFS…).

**PV après suppression du PVC :** avec **`Retain`**, le PV est conservé avec ses données, en état `Released` (un administrateur doit le nettoyer ou le réattribuer). Avec **`Delete`** (StorageClass `standard`), le PV **et les données** sont supprimés automatiquement.

**Deployment vs StatefulSet :**

| | Deployment | StatefulSet |
|---|---|---|
| Nom des Pods | aléatoire (`webapp-7c9f…`) | stable et ordonné (`redis-0`, `redis-1`) |
| Stockage | partagé ou aucun | un PVC dédié par Pod (`volumeClaimTemplates`) |
| Ordre de démarrage | parallèle | séquentiel (0, puis 1, puis 2) ; arrêt en ordre inverse |
| Si un Pod est recréé | nouveau nom, nouvelle identité | **même nom, même PVC** |
| Usage | applications sans état (web, API) | bases de données, files de messages |
