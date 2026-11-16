# TP 4.8 – Mise à l'échelle, mises à jour sans interruption et retour arrière

**Objectif :** faire évoluer une application en production **sans coupure** : scaling manuel et automatique (HPA), rolling update contrôlé, rollback en une commande.

**Statut :** ✅ réalisé et vérifié (défi compris) – étapes 1 à 6 tapées en partie par Romaric – preuves dans [`preuves/`](preuves/)

## 🧠 À mémoriser

| Commande | À quoi elle sert |
|---|---|
| `kubectl scale deployment webapp --replicas=5` | change le nombre de copies (impératif, le fichier n'est pas modifié) |
| `kubectl set image deployment/webapp webapp=image:2.0.0` | change l'image → lance un rolling update |
| `kubectl rollout status deployment/webapp` | attend la fin d'un déploiement (échoue si bloqué) |
| `kubectl rollout history deployment/webapp` | liste les versions (révisions) et leur `change-cause` |
| `kubectl rollout undo deployment/webapp [--to-revision=N]` | revient à la version précédente (ou à la révision N) |
| `kubectl annotate deployment/webapp kubernetes.io/change-cause="…" --overwrite` | décrit la version dans l'historique |
| `kubectl get rs -l app=webapp` | un ReplicaSet par version du modèle de Pod |
| `kubectl get hpa -w` | suit l'autoscaler (CPU actuel / objectif, nombre de réplicas) |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`30-webapp.yaml`](30-webapp.yaml) | Deployment : `replicas: 4`, `revisionHistoryLimit: 5`, stratégie `RollingUpdate` (`maxSurge: 1`, `maxUnavailable: 0`), **readinessProbe** `/ready`, `requests`/`limits` CPU-RAM |
| [`40-hpa.yaml`](40-hpa.yaml) | HorizontalPodAutoscaler : 2 à 8 réplicas, objectif 50 % du CPU demandé |

Les images `nedstudio/legeni-webapp:1.0.0` et `2.0.0` ont été construites depuis `legeni-webapp` (`--build-arg APP_VERSION=…`) et chargées dans Minikube (`minikube image load`).

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `docker build --build-arg APP_VERSION=2.0.0 -t nedstudio/legeni-webapp:2.0.0 .` | construit une version distincte de l'image |
| `minikube image load nedstudio/legeni-webapp:2.0.0` | rend l'image disponible dans le nœud Minikube |
| `while true; do curl -s -m1 $URL/api/info \|\| echo "❌ ERREUR"; echo; sleep 0.5; done` | « client » qui interroge l'application en continu pour voir les coupures |
| `kubectl scale deployment webapp --replicas=5` / `=2` | scaling manuel |
| `kubectl get pods -l app=webapp -o wide` | Pods, IP, nœud |
| `kubectl delete pod -l app=webapp --wait=false` | supprime tous les Pods → le ReplicaSet les recrée |
| `kubectl describe rs <rs> \| tail -5` | événements `SuccessfulCreate` du contrôleur ReplicaSet |
| `kubectl apply -f 30-webapp.yaml` | applique la stratégie et remet l'état décrit dans le fichier |
| `kubectl set image deployment/webapp webapp=nedstudio/legeni-webapp:2.0.0` | rolling update vers la 2.0.0 |
| `kubectl annotate deployment/webapp kubernetes.io/change-cause="passage en 2.0.0" --overwrite` | note la raison du changement (guillemets obligatoires) |
| `kubectl rollout status deployment/webapp --timeout=60s` | suit la mise à jour ; échoue au bout de 60 s si elle est bloquée |
| `kubectl rollout history deployment/webapp` | historique des révisions |
| `kubectl rollout undo deployment/webapp` | rollback |
| `kubectl apply -f 40-hpa.yaml` / `kubectl get hpa webapp -w` | crée et suit l'autoscaler |
| `kubectl run charge --image=busybox:1.36 --restart=Never -- sh -c 'while true; do wget -q -O- http://webapp/ >/dev/null; done'` | génère de la charge depuis le cluster |
| `kubectl get events --sort-by=.lastTimestamp` | événements du namespace (dont `SuccessfulRescale` de l'HPA) |
| `kubectl patch deploy webapp --type=merge -p '{"spec":{"strategy":{…}}}'` | défi : change la stratégie de mise à jour |

## Résultats obtenus
- **Scaling** : 5 réplicas (même ReplicaSet `…597b45dd89`, 5 IP différentes), la boucle voit 5 hostnames ; retour à 2 : Kubernetes choisit lui-même les Pods à supprimer.
- **Auto-réparation** : tous les Pods supprimés → recréés par le `replicaset-controller` (quelques secondes de coupure, puisqu'ils étaient **tous** supprimés en même temps).
- **Rolling update 1.0.0 → 2.0.0** : remplacement 1 par 1 (`1 out of 4`, `2 out of 4`…), 1.0.0 et 2.0.0 cohabitent puis seule 2.0.0 répond ; nouveau ReplicaSet à 4, anciens à 0.
- **Découverte importante** : **sans readinessProbe**, le rolling update provoquait des erreurs (8 erreurs, `04a`) : un nouveau Pod recevait du trafic avant que gunicorn écoute. **Avec** la readinessProbe (`04b`) : 51 réponses v1.0.0, 45 v2.0.0, **1 seule erreur**. La probe a donc été ajoutée au fichier (elle est détaillée au TP 4.9).
- **Image 9.9.9** : 1 Pod `ErrImagePull`, les **4 anciens restent `Running`** (`maxUnavailable: 0`) → aucune coupure ; `rollout history` montre les `change-cause` ; `rollout undo` → retour à la 2.0.0.
- **HPA** : sous charge, `TARGETS` 64 % puis 82 % (> 50 %) → **8 réplicas** (le maximum) ; charge arrêtée → `All metrics below target` → **2 réplicas** après ~5 min de stabilisation.
- **Défi** (même mise à jour, boucle 2 requêtes/s, 4 réplicas) :

| Stratégie | Erreurs | Comportement |
|---|---|---|
| `RollingUpdate` maxSurge 1 / maxUnavailable 0 | 2 | jusqu'à 5 Pods, jamais moins de 4 prêts |
| `RollingUpdate` maxSurge 0 / maxUnavailable 1 | 1 | jamais plus de 4 Pods, mais parfois seulement 3 prêts (capacité réduite) |
| `Recreate` | **21 d'affilée (~10 s)** | tous les anciens Pods supprimés **puis** les nouveaux créés → **coupure** |

  Les 1 ou 2 erreurs isolées du rolling update viennent de connexions coupées au moment où un ancien Pod s'arrête (on peut les supprimer avec un `preStop` / arrêt progressif).

## Réponses aux questions

**Quel objet recrée les Pods ?** Le **ReplicaSet** (contrôleur `replicaset-controller` du `kube-controller-manager`), créé et piloté par le Deployment. Il compare en boucle le nombre de Pods voulu au nombre réel.

**Pourquoi un nouveau ReplicaSet à chaque mise à jour ?** Un ReplicaSet correspond à **un modèle de Pod** (image, variables, probes…). Changer l'image crée un nouveau ReplicaSet ; l'ancien est conservé à 0 (dans la limite de `revisionHistoryLimit`) : c'est ce qui rend le rollback instantané. Le scaling, lui, ne change que le nombre de Pods, donc pas de nouveau ReplicaSet.

**Défi – cas d'usage :**
- `maxSurge: 1 / maxUnavailable: 0` : cas général en production, aucune perte de capacité (il faut un peu de ressources en plus pendant la mise à jour).
- `maxSurge: 0 / maxUnavailable: 1` : cluster très contraint en ressources, on accepte une capacité réduite pendant la mise à jour.
- `Recreate` : quand deux versions ne peuvent **pas** cohabiter (changement de schéma de base incompatible, volume `ReadWriteOnce`, base de données comme au TP 4.5) ; on accepte une courte coupure.

**Attention à `rollout undo` et `set image`** : ils modifient le cluster, pas le fichier. kubectl l'indique (`Rolling back will not update the last-applied-configuration annotation`). En équipe, on change le tag dans le YAML, on commite, puis `kubectl apply` (ou `git revert` pour revenir en arrière).
