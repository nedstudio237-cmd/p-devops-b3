# TP 4.6 – Jobs, CronJobs, DaemonSets et initContainers

**Objectif :** exécuter une **tâche ponctuelle** (Job), une **tâche planifiée** (CronJob), un **agent sur chaque nœud** (DaemonSet), et **préparer** un Pod avant son démarrage (initContainer).

**Statut :** ✅ réalisé et vérifié (défi compris) – preuves dans [`preuves/`](preuves/)

| Objet | Le Pod… | Exemple |
|---|---|---|
| Deployment | tourne en permanence, N réplicas interchangeables | site web, API |
| **Job** | s'exécute jusqu'à la réussite, puis s'arrête | migration, import |
| **CronJob** | crée un Job selon un horaire | sauvegarde nocturne |
| **DaemonSet** | tourne en un exemplaire par nœud | agent de logs, supervision |

## 🧠 À mémoriser

| Commande | À quoi elle sert |
|---|---|
| `kubectl get jobs,cronjobs` | liste les tâches ponctuelles et planifiées |
| `kubectl logs job/<nom>` | résultat d'un Job |
| `kubectl wait --for=condition=complete job/<nom> --timeout=120s` | attend la réussite d'un Job (pipelines) |
| `kubectl create job --from=cronjob/<nom> <job>` | lance un CronJob immédiatement |
| `kubectl patch cronjob <nom> -p '{"spec":{"suspend":true}}'` | met un CronJob en pause |
| `kubectl get ds -A` | liste les DaemonSets (un Pod par nœud) |
| `kubectl logs <pod> -c <initContainer>` | logs d'un initContainer bloqué (`Init:0/1`) |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`10-job-pi.yaml`](10-job-pi.yaml) | Job : 500 décimales de π (`backoffLimit`, `ttlSecondsAfterFinished`) |
| [`11-job-echec.yaml`](11-job-echec.yaml) | Job qui échoue (`backoffLimit: 2` → 3 essais) |
| [`12-job-lots.yaml`](12-job-lots.yaml) | Job parallèle indexé : 6 lots, 2 en même temps |
| [`20-cronjob-sante.yaml`](20-cronjob-sante.yaml) | CronJob : contrôle de santé de `webapp` chaque minute |
| [`21-cronjob-sauvegarde.yaml`](21-cronjob-sauvegarde.yaml) | PVC + CronJob de sauvegarde (garde les 5 dernières) |
| [`30-daemonset-agent.yaml`](30-daemonset-agent.yaml) | DaemonSet : agent par nœud (logs du nœud en `hostPath`, `NODE_NAME` par l'API descendante) |
| [`40-webapp-init.yaml`](40-webapp-init.yaml) | Deployment avec initContainer qui attend Redis (+ `enableServiceLinks: false`, voir plus bas) |
| [`50-migration.yaml`](50-migration.yaml) | Défi : Job de migration (attend Redis, `SET visits 1000`) |

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `kubectl create namespace batch && kubectl config set-context --current --namespace=batch` | Namespace de travail |
| `kubectl apply -f 10-job-pi.yaml` | Lance un Job |
| `kubectl get jobs,pods -w` | Suit le Job (`Completed`, `1/1`) |
| `kubectl logs job/calcul-pi` | Résultat du Job |
| `kubectl wait --for=condition=complete job/calcul-pi --timeout=120s` | Attend la réussite (utilisé dans les pipelines) |
| `kubectl wait --for=condition=failed job/migration-ratee` | Attend l'échec définitif |
| `kubectl get job migration-ratee -o jsonpath='{.status.conditions}'` | Conditions du Job (`Failed`, `BackoffLimitExceeded`) |
| `kubectl get pods -l job-name=traitement-lots` | Pods d'un Job (label `job-name` ajouté automatiquement) |
| `kubectl create deployment webapp --image=… --port=5000` / `kubectl expose …` | Application surveillée par le CronJob |
| `kubectl get cronjob controle-sante` | Planning, dernier déclenchement |
| `kubectl scale deployment webapp --replicas=0` | Simule une panne |
| `kubectl create job --from=cronjob/controle-sante controle-manuel` | Lance un CronJob immédiatement, sans attendre l'horaire |
| `kubectl patch cronjob sauvegarde -p '{"spec":{"suspend":true}}'` | Met un CronJob en pause sans le supprimer |
| `kubectl get daemonset agent-noeud` / `kubectl logs ds/agent-noeud` | État et logs du DaemonSet |
| `kubectl get ds -A` | DaemonSets du cluster |
| `kubectl logs deploy/webapp-redis -c attendre-redis` | Logs de l'initContainer |
| `kubectl apply -f 50-migration.yaml && kubectl wait --for=condition=complete job/migration-compteur && kubectl rollout restart deployment/webapp-redis && kubectl rollout status deployment/webapp-redis` | Défi : enchaînement « migration → attente → redémarrage » comme dans un pipeline |
| `kubectl delete namespace batch` | Nettoyage |

## Résultats obtenus
- `calcul-pi` : `Complete 1/1` en 3 s, `3.14159265358979323846…`.
- `migration-ratee` : 3 Pods en `Error` (1 essai + 2 nouvelles tentatives), condition `Failed=True (BackoffLimitExceeded)`, `kubectl wait --for=condition=failed` → `condition met`.
- `traitement-lots` : `6/6`, lots 0 à 5, **jamais plus de 2 Pods Running** à la fois.
- `controle-sante` : Jobs `Complete` chaque minute (`{"status":"ok"} → OK`), **`Failed 0/1` pendant la panne**, OK après remise en route ; lancement manuel OK.
- `sauvegarde-1` : `Sauvegarde : /backup/info-20261112-0205.json` dans le PVC ; CronJob suspendu.
- `agent-noeud` : `DESIRED 1 / READY 1` (un nœud). Bonus `minikube node add` non fait (RAM insuffisante).
- initContainer : `Init:0/1` tant que Redis n'existe pas, puis `Running` après création de Redis.
- Défi : compteur à **1001** puis 1002, `Stockage du compteur : redis`.

### Problème rencontré et résolu (défi)
Après `kubectl rollout restart`, le nouveau Pod `webapp-redis` plantait en boucle :
`ValueError: invalid literal for int() with base 10: 'tcp://10.108.35.149:6379'`.
**Cause :** pour chaque Service, Kubernetes injecte des variables d'environnement (*service links*) dans les Pods créés **après** lui ; le Service `redis` crée `REDIS_PORT=tcp://<ip>:6379`, qui écrase la valeur par défaut `6379` attendue par l'application. Le premier Pod, créé **avant** le Service, n'était pas touché.
**Correction :** `enableServiceLinks: false` dans le template du Pod (on utilise le DNS `redis`, pas ces variables).

## Réponses aux questions

**Pourquoi lancer la migration dans un Job *avant* de mettre à jour le Deployment ?** La nouvelle version de l'application a besoin du nouveau schéma de base. Le Job s'exécute une seule fois, jusqu'à la réussite, et le pipeline attend son résultat (`kubectl wait`) : s'il échoue, on **n'a pas déployé** la nouvelle version (l'ancienne continue de tourner). Faite dans les Pods de l'application, la migration serait lancée N fois en parallèle (un par réplica) et un échec bloquerait le démarrage des Pods.

**Deux outils réels déployés en DaemonSet :** dans ce cluster, `kube-proxy` (règles réseau des Services) et `kindnet` (réseau des Pods) ; ailleurs : Fluent Bit / Fluentd (collecte de logs), Prometheus `node-exporter` (métriques des nœuds), agents Datadog, Calico / Cilium (réseau).
