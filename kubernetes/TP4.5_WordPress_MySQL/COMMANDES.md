# TP 4.5 – WordPress + MySQL : une application à état sur Kubernetes

**Objectif :** déployer une application en deux tiers (WordPress + MySQL) en combinant **Secret**, **PersistentVolumeClaim**, **Deployment** et **Services**, et prouver que les données survivent à la perte du Pod de base de données.

**Statut :** ✅ réalisé et vérifié (défi compris) – preuves dans [`preuves/`](preuves/)

```
Navigateur ──▶ Service wordpress (NodePort) ──▶ Pod WordPress ──▶ Service mysql (headless) ──▶ Pod MySQL ──▶ PVC ──▶ volume
```

## 🧠 À mémoriser

| Commande | À quoi elle sert |
|---|---|
| `kubectl create namespace <ns>` | crée un espace de noms |
| `kubectl config set-context --current --namespace=<ns>` | change le namespace par défaut |
| `kubectl create secret generic <nom> --from-literal=clé=valeur` | crée un Secret hors Git |
| `kubectl get secret <nom> -o jsonpath='{.data.clé}' \| base64 -d` | lit un Secret (base64 ≠ chiffrement) |
| `kubectl get pvc,pv` | volumes demandés et volumes créés (`Bound`) |
| `kubectl exec deploy/<nom> -- <commande>` | lance une commande dans un Pod du Deployment |
| `kubectl delete namespace <ns>` | supprime tout le namespace, données comprises |

## Fichiers réalisés (un fichier par ressource, numérotés)

| Fichier | Contenu |
|---|---|
| [`00-namespace.yaml`](00-namespace.yaml) | Namespace `wordpress` (généré avec `--dry-run=client -o yaml`) |
| [`10-mysql-pvc.yaml`](10-mysql-pvc.yaml) | PVC `mysql-pv-claim` 2 Gi, `ReadWriteOnce` |
| [`20-mysql.yaml`](20-mysql.yaml) | Deployment MySQL 8.0 (`strategy: Recreate`, mot de passe depuis le Secret, volume) + Service headless `mysql` |
| [`30-wordpress.yaml`](30-wordpress.yaml) | Deployment WordPress (`WORDPRESS_DB_HOST=mysql`, mot de passe depuis le Secret) + Service NodePort |
| [`40-phpmyadmin.yaml`](40-phpmyadmin.yaml) | Défi : phpMyAdmin **sans Service** (accès par port-forward uniquement) |

Le Secret `mysql-pass` est créé en ligne de commande, **hors Git**.

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `kubectl create namespace wordpress --dry-run=client -o yaml > 00-namespace.yaml` | Génère le manifeste du namespace |
| `kubectl config set-context --current --namespace=wordpress` | Fait de `wordpress` le namespace par défaut de kubectl |
| `kubectl create secret generic mysql-pass --from-literal=password="$(openssl rand -base64 12)"` | Crée un Secret avec un mot de passe aléatoire (jamais écrit dans un fichier) |
| `kubectl get secret mysql-pass -o jsonpath='{.data.password}' \| base64 -d` | Lit le Secret (stocké en base64, **pas chiffré**) |
| `kubectl get pvc,pv` / `kubectl get storageclass` | Volume réservé (`Bound`) et classe de stockage qui l'a créé (`standard`) |
| `kubectl logs -f deploy/mysql` | Suit le démarrage de MySQL (`ready for connections`) |
| `minikube service wordpress-service -n wordpress --url` | URL du site |
| `kubectl exec deploy/wordpress -- getent hosts mysql` | Vérifie la résolution DNS du Service `mysql` depuis WordPress |
| `kubectl exec deploy/mysql -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT …"'` | Requête SQL dans la base |
| `kubectl delete pod -l app=mysql` | Simule la perte du serveur de base de données |
| `kubectl delete -f 20-mysql.yaml` puis `kubectl apply -f 20-mysql.yaml` | Supprime et recrée MySQL : le PVC (les données) reste |
| `grep -ri password *.yaml` | Vérifie qu'aucun mot de passe n'est en clair (seulement des `secretKeyRef`) |
| `kubectl port-forward deploy/phpmyadmin 8085:80` | Défi : accès à phpMyAdmin par tunnel, sans l'exposer |
| `kubectl delete namespace wordpress` | Supprime **tout** le namespace, PVC et données compris |

## Résultats obtenus
- PVC `Bound` (PV créé automatiquement par la StorageClass `standard`, `k8s.io/minikube-hostpath`).
- WordPress installé (titre « TP DevOps B3 ») ; article **« Test de persistance »** publié (installation et publication faites par HTTP : formulaire `install.php` + XML-RPC).
- `getent hosts mysql` → `10.244.0.34 mysql.wordpress.svc.cluster.local` (headless : IP du Pod directement).
- Suppression du Pod MySQL → nouveau Pod, **article toujours présent** ; suppression du Deployment + Service MySQL → PVC toujours `Bound`, après `apply` **article toujours présent**.
- Défi : `kubectl get svc` ne montre que `mysql` et `wordpress-service` ; via `port-forward` → `<title>phpMyAdmin</title>`, connexion `root` réussie.
- `kubectl delete namespace wordpress` → plus aucun PV : les données ont été supprimées.

## Réponses aux questions

**1. Pourquoi `strategy: Recreate` pour une base de données ?** `RollingUpdate` démarre le nouveau Pod **avant** d'arrêter l'ancien : deux MySQL écriraient en même temps dans les mêmes fichiers (corruption), et le volume `ReadWriteOnce` ne peut de toute façon être monté que par un nœud. `Recreate` arrête l'ancien Pod **puis** démarre le nouveau (courte coupure, mais données cohérentes).

**2. Pourquoi le Service MySQL n'est-il pas exposé à l'extérieur ?** Seul WordPress, **dans le cluster**, a besoin de la base. L'exposer serait une faille de sécurité (attaques directes sur la base). Le Service headless fournit juste un nom DNS interne (`mysql`).

**Que se passe-t-il avec `kubectl delete -f .` ? Avec `kubectl delete namespace wordpress` ? Précautions ?** `kubectl delete -f .` supprime aussi `10-mysql-pvc.yaml`, donc le PVC ; avec la politique `Delete` de la StorageClass, le PV et **les données sont détruits**. `kubectl delete namespace` supprime tout ce qu'il contient, y compris le PVC et le Secret (constaté). En production : **sauvegardes** régulières de la base, `persistentVolumeReclaimPolicy: Retain` (le volume survit à la suppression du PVC), séparer le PVC des manifestes de l'application, restreindre les droits de suppression (RBAC), ou utiliser une base managée.
