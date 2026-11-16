# TP 4.13 – Dépannage Kubernetes : 6 pannes à résoudre

**Objectif :** acquérir une **méthode** de diagnostic. En production, on passe plus de temps à comprendre pourquoi « ça ne marche pas » qu'à écrire du YAML.

**Statut :** ✅ les 6 pannes résolues + défi (panne originale) – preuves dans [`preuves/`](preuves/)

## 🧠 À mémoriser : la méthode

| Ordre | Commande | Ce qu'on y cherche |
|---|---|---|
| 1 | `kubectl get pods` | `STATUS`, `READY`, `RESTARTS` : quel type de panne ? |
| 2 | `kubectl describe pod <pod>` | section **Events** en bas : la cause est presque toujours là |
| 3 | `kubectl logs <pod> --previous` | l'erreur de l'application **avant** son dernier crash |
| 4 | `kubectl describe svc <svc>` | ligne **Endpoints** : le Service trouve-t-il des Pods prêts ? |
| 5 | `kubectl get events --sort-by=.lastTimestamp` | tout ce qui s'est passé récemment dans le namespace |
| 6 | `kubectl run t --image=busybox:1.36 -i --rm --restart=Never -- wget -qO- http://<svc>` | tester le réseau **depuis l'intérieur** du cluster |
| 7 | `kubectl exec -it <pod> -- sh` | entrer dans le conteneur pour vérifier (ports, fichiers, variables) |

| Symptôme | Causes fréquentes |
|---|---|
| `ImagePullBackOff` / `ErrImagePull` | tag inexistant, faute de frappe, registre privé sans `imagePullSecrets` |
| `CrashLoopBackOff` / `Error` | l'application plante au démarrage : lire `logs --previous` |
| `Pending` | ressources insuffisantes, PVC non lié, quota |
| `Running` mais `0/1 READY` | readinessProbe en échec |
| Service sans réponse | `selector` ≠ labels des Pods, mauvais `targetPort` |
| `CreateContainerConfigError` | ConfigMap ou Secret référencé inexistant |

## Fichiers réalisés

| Fichier cassé | Fichier corrigé |
|---|---|
| [`panne1.yaml`](panne1.yaml) | [`panne1-corrige.yaml`](panne1-corrige.yaml) |
| [`panne2.yaml`](panne2.yaml) | [`panne2-corrige.yaml`](panne2-corrige.yaml) |
| [`panne3.yaml`](panne3.yaml) | [`panne3-corrige.yaml`](panne3-corrige.yaml) |
| [`panne4.yaml`](panne4.yaml) | [`panne4-corrige.yaml`](panne4-corrige.yaml) |
| [`panne5.yaml`](panne5.yaml) | [`panne5-corrige.yaml`](panne5-corrige.yaml) |
| [`panne6.yaml`](panne6.yaml) | [`panne6-corrige.yaml`](panne6-corrige.yaml) |
| [`panne7-originale.yaml`](panne7-originale.yaml) (défi) | [`panne7-corrige.yaml`](panne7-corrige.yaml) |

## Tableau de diagnostic

| # | Symptôme | Commande clé | Cause trouvée | Correction |
|---|---|---|---|---|
| 1 | `ErrImagePull` / `ImagePullBackOff` | `describe pod` / events → `Failed to pull image "nginx:1.27-alpnie": … NotFound` | faute de frappe dans le tag (`alpnie`) | `nginx:1.27-alpine` |
| 2 | `Error`, RESTARTS qui monte (CrashLoopBackOff) | `logs deploy/api --previous` → `ModuleNotFoundError: No module named 'flask'` ; `Exit Code: 1` | `python:3.12-slim` ne contient pas Flask, et le script se termine aussitôt | image de l'application `nedstudio/legeni-webapp:2.0.0` (Flask 3.1.0, serveur durable) |
| 3 | `wget … Connection refused` sur `http://web` (Pods `Running`) | `describe svc web` → `Selector: app=website`, `Endpoints:` **vide** | le selector ne correspond à aucun label (`app: web`) | `selector: {app: web}` |
| 4 | `wget … Connection refused` sur `http://app` | `describe svc app` → `Endpoints: 10.244.0.105:8080` ; `netstat` dans le Pod → nginx écoute sur **80** | `targetPort: 8080` alors que nginx écoute sur 80 | `targetPort: 80` |
| 5 | `CreateContainerConfigError` | `describe pod` → `Error: configmap "config-app" not found` | ConfigMap inexistante | créer la ConfigMap `config-app` (ou `optional: true`) |
| 6 | Pod `Pending`, PVC `Pending` | events → `pod has unbound immediate PersistentVolumeClaims` ; PVC → `storageclass "rapide" not found` | StorageClass inexistante | `storageClassName: standard` ; PVC **immuable** → `kubectl delete pvc` puis recréer |
| 7 (défi) | Pods `Running` mais `0/1`, site sans réponse | `describe svc` → Endpoints vide ; events → `Readiness probe failed: … :8080 … connection refused` | sonde de readiness sur le port 8080, nginx écoute sur 80 | `readinessProbe.httpGet.port: 80` – résolu en **8 s** avec 4 commandes |

## Commandes et rôle (en plus de la méthode)

| Commande | Rôle |
|---|---|
| `kubectl create namespace depannage` / `kubectl config set-context --current --namespace=depannage` | espace de travail isolé |
| `kubectl get pods,svc,pvc` | vue d'ensemble de plusieurs types d'objets |
| `kubectl get events --field-selector involvedObject.name=<objet>` | événements d'un seul objet |
| `kubectl get events --field-selector reason=Unhealthy` | événements d'un type précis (ici sondes en échec) |
| `kubectl exec deploy/app -- netstat -tln` | ports réellement écoutés dans le conteneur |
| `kubectl get storageclass` | classes de stockage existantes |
| `kubectl delete pvc data` | un PVC ne se modifie pas : on le supprime pour le recréer |
| `kubectl delete namespace depannage` | nettoyage complet |

## Résultats obtenus
- État initial : `front` en `ErrImagePull`, `api` en `Error` (3 redémarrages), `conf` en `CreateContainerConfigError`, `db` et PVC `data` en `Pending`, `web` et `app` « Running » mais inaccessibles.
- Après corrections : **les 8 Pods `Running 1/1`**, PVC `Bound` (classe `standard`), `http://web` et `http://app` → `Welcome to nginx!`, `APP_ENV=depannage` lu depuis la ConfigMap, Flask 3.1.0 présent dans `api`.

## À retenir
- Les pannes 3, 4 et 7 sont les plus pièges : **tout semble « Running »**, mais le site ne répond pas → regarder les **Endpoints** du Service.
- **Lire avant d'agir** : `describe` et ses Events donnent presque toujours la cause exacte ; `logs --previous` pour un conteneur qui plante.
