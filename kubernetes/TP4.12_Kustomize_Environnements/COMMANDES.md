# TP 4.12 – Gérer plusieurs environnements avec Kustomize

**Objectif :** déployer **les mêmes manifestes** en `staging` et en `prod` avec des différences maîtrisées (namespace, réplicas, couleur, version d'image), sans copier-coller de YAML. Kustomize est intégré à `kubectl` (`-k`).

**Statut :** ✅ réalisé et vérifié (défi + bonus Helm) – preuves dans [`preuves/`](preuves/)

## 🧠 À mémoriser

| Commande / notion | À quoi ça sert |
|---|---|
| `base/` + `overlays/<env>/` | YAML commun une seule fois + petites différences par environnement |
| `kubectl kustomize overlays/prod` | affiche le YAML final **sans rien appliquer** |
| `kubectl apply -k overlays/prod` | applique un overlay (`-k` = dossier Kustomize, `-f` = fichier) |
| `kubectl diff -k overlays/prod` | montre ce qui va changer dans le cluster avant d'appliquer |
| `kubectl delete -k overlays/staging` | supprime tout un environnement |
| `images: newName / newTag` | change l'image et la version sans toucher au Deployment |
| `configMapGenerator` | génère une ConfigMap avec suffixe de hash → modifier la config relance les Pods automatiquement |
| `patches:` | modifie un champ précis de la base (ex. `replicas: 4` en prod) |

## Fichiers réalisés ([`k8s/`](k8s/))

```
k8s/
├── base/
│   ├── kustomization.yaml     # ressources + label part-of + configMapGenerator (REDIS_HOST, REDIS_PORT)
│   ├── redis.yaml             # Service + StatefulSet Redis (sondes, ressources, PVC) – sans namespace
│   └── webapp.yaml            # Deployment (image "legeni-webapp" sans tag, 2 réplicas) + Service ClusterIP
└── overlays/
    ├── staging/kustomization.yaml          # legeni-staging, 2.0.0, orange
    ├── prod/kustomization.yaml             # legeni-prod, 4 réplicas, 1.0.0 puis 2.0.0, vert
    ├── prod/replicas-patch.yaml
    ├── dev/kustomization.yaml              # défi : legeni-kdev, 1 réplica, violet
    └── dev/dev-patch.yaml                  # défi : replicas 1 + imagePullPolicy IfNotPresent
```
L'overlay `dev` utilise le namespace `legeni-kdev` car `legeni-dev` est déjà occupé par l'application des TPs 4.7 à 4.11.

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `mkdir -p k8s/base k8s/overlays/{staging,prod}` | arborescence base / overlays |
| `kubectl kustomize overlays/staging \| less` | rendu final d'un environnement |
| `diff <(kubectl kustomize overlays/staging) <(kubectl kustomize overlays/prod)` | compare deux environnements |
| `kubectl create namespace legeni-$env --dry-run=client -o yaml \| kubectl apply -f -` | crée le namespace s'il n'existe pas (idempotent) |
| `kubectl create secret generic redis-secret -n legeni-$env --from-literal=… --dry-run=client -o yaml \| kubectl apply -f -` | crée le Secret (hors Git) de façon idempotente |
| `kubectl apply -k overlays/$env` | déploie un environnement |
| `kubectl get deploy -A -l app.kubernetes.io/part-of=legeni` | tous les environnements de l'application |
| `sed -i 's/newTag: .*/newTag: "2.0.0"/' overlays/prod/kustomization.yaml` | promotion d'une version (ce que fera Jenkins) |
| `git diff overlays/prod` | la promotion = un commit d'une ligne |
| `kubectl diff -k overlays/prod` | ce qui va changer avant d'appliquer |
| `kubectl rollout status deploy/webapp -n legeni-prod` | suit le déploiement de la nouvelle version |
| `kubectl delete -k overlays/staging` | supprime l'environnement staging |
| `helm install redis oci://registry-1.docker.io/bitnamicharts/redis -n helm-demo --create-namespace --set …` | bonus : installe un logiciel complet à partir d'un chart Helm |
| `helm list` / `helm get values` / `helm template` / `helm uninstall` | releases installées, valeurs utilisées, YAML généré, désinstallation |

## Résultats obtenus
- `kubectl kustomize overlays/prod` : `namespace: legeni-prod` sur les 5 objets, image `nedstudio/legeni-webapp:1.0.0`, `replicas: 4`, ConfigMap `webapp-config-t5fkchbk2t` (suffixe de hash).
- `diff staging/prod` : seules différences = namespace, label `env`, image, réplicas, `APP_ENV`, `APP_COLOR` (et le hash de la ConfigMap).
- Les deux environnements tournent **en parallèle** : `legeni-staging` 2/2 en **2.0.0**, `APP_COLOR=#bf8700` ; `legeni-prod` 4/4 en **1.0.0**, `APP_COLOR=#2da44e`.
- **Promotion** : `git diff` → une seule ligne (`newTag: "1.0.0"` → `"2.0.0"`) ; `kubectl diff -k` → l'image change ; après `apply -k`, la prod répond `"version":"2.0.0"`.
- **Défi dev** : `1 réplica, nedstudio/legeni-webapp:2.0.0, pull=IfNotPresent`.
- `delete -k overlays/staging` : Deployment et StatefulSet supprimés ; le **PVC `data-redis-0` reste** (les données ne sont jamais supprimées automatiquement avec un StatefulSet).
- **Bonus Helm** : chart Bitnami Redis 28.3.12 installé (`STATUS: deployed`), Pod `redis-master-0` 1/1, PVC 8 Gi, 10 objets générés par le chart ; avertissement Bitnami : depuis août 2025, le catalogue gratuit d'images est réduit. Release désinstallée ensuite.

## Réponses aux questions

**Pourquoi `configMapGenerator` ?** Il ajoute un hash au nom de la ConfigMap et met à jour la référence dans le Deployment : si la configuration change, le nom change, donc le modèle de Pod change, donc **rolling update automatique** (plus besoin du `rollout restart` du TP 4.7).

**Pourquoi la promotion par modification d'un fichier ?** La version déployée en prod est écrite dans Git : l'**historique Git devient l'historique des déploiements** (qui, quand, quoi), revue possible en pull request, retour arrière par `git revert` (principe *GitOps*).

**Défi – Kustomize ou Helm ?**

| | Kustomize | Helm |
|---|---|---|
| Principe | **patchs** sur du YAML Kubernetes valide | **templates** (Go) + fichier de **valeurs** |
| Avantages | intégré à kubectl, pas de langage de template, YAML lisible et testable tel quel, idéal pour ses propres applications | réutilisation et partage (charts publics : Redis, PostgreSQL…), paramétrage riche, gestion des **releases** (`helm upgrade`, `helm rollback`, `helm list`) |
| Inconvénients | pas de logique (boucles, conditions), pas de notion de release/version, moins adapté au partage | templates difficiles à lire et à déboguer, dépendance aux éditeurs de charts (cf. changement de politique Bitnami), outil en plus à installer |
| Usage typique | variantes dev/staging/prod de **nos** manifestes | installer des **logiciels tiers** dans le cluster |
