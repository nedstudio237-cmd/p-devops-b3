# TP 4.11 – Exposer ses applications avec un Ingress

**Objectif :** remplacer les ports NodePort (30080, 31xxx…) par de **vrais noms de domaine** routés par un reverse proxy unique : l'Ingress Controller (nginx).

**Statut :** ✅ réalisé et vérifié (défi rédigé, non appliqué comme demandé) – preuves dans [`preuves/`](preuves/)

```
                         ┌──────────── Ingress Controller (nginx) ────────────┐
 legeni.local     ─────▶ │ host: legeni.local          → Service webapp:80    │
 blog.legeni.local ────▶ │ host: blog.legeni.local     → Service wordpress:80 │
                         └────────────────────────────────────────────────────┘
```

## 🧠 À mémoriser

| Commande / notion | À quoi ça sert |
|---|---|
| Ingress | règles HTTP « nom de domaine / chemin → Service » ; un seul point d'entrée pour plusieurs applications |
| Ingress Controller | le reverse proxy (ici nginx) qui applique ces règles ; activé par `minikube addons enable ingress` |
| `kubectl get ingress -A` | liste les Ingress, leurs noms d'hôte et leur adresse |
| `kubectl describe ingress <nom>` | règles détaillées et Pods réellement ciblés |
| `kubectl get ingressclass` | contrôleurs disponibles (`nginx`) |
| `echo "$(minikube ip) legeni.local" \| sudo tee -a /etc/hosts` | fait pointer un nom vers le cluster (DNS local) |
| `kubectl create secret tls <nom> --cert=tls.crt --key=tls.key` | stocke un certificat pour le HTTPS |
| `curl -k https://…` | teste en HTTPS en acceptant un certificat auto-signé |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`30-webapp.yaml`](30-webapp.yaml) | Service `webapp` repassé en **ClusterIP** (plus de nodePort 30080) |
| [`60-ingress.yaml`](60-ingress.yaml) | Ingress `legeni` : hôte `legeni.local`, chemins `/api` et `/`, **TLS** avec le Secret `legeni-tls` |
| [`blog-ingress.yaml`](blog-ingress.yaml) | Ingress `blog` (namespace `default`) : `blog.legeni.local` → `wordpress-service` |
| [`defi-cert-manager.yaml`](defi-cert-manager.yaml) | Défi : `ClusterIssuer` Let's Encrypt + annotation `cert-manager.io/cluster-issuer` (non appliqué) |

`tls.key` / `tls.crt` (certificat auto-signé) sont exclus de Git (`.gitignore`). WordPress a été redéployé dans `default` à partir des fichiers du TP 4.5.

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `kubectl get pods -n ingress-nginx` | vérifie que le contrôleur Ingress tourne |
| `kubectl get ingressclass` | classe d'Ingress disponible (`nginx`) |
| `kubectl apply -f 30-webapp.yaml` | passe le Service en ClusterIP (accessible seulement dans le cluster) |
| `kubectl apply -f 60-ingress.yaml` | crée la règle `legeni.local → webapp` |
| `kubectl get ingress -w` | attend qu'une `ADDRESS` (IP du contrôleur) apparaisse |
| `echo "$(minikube ip) legeni.local blog.legeni.local" \| sudo tee -a /etc/hosts` | résolution de nom locale |
| `curl -s http://legeni.local/api/info` | accès par nom de domaine, sans numéro de port |
| `kubectl apply -f blog-ingress.yaml` | 2e application derrière le même contrôleur |
| `curl -sI http://blog.legeni.local \| head -1` | code de réponse de WordPress |
| `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=legeni.local"` | crée un certificat auto-signé |
| `kubectl create secret tls legeni-tls -n legeni-dev --cert=tls.crt --key=tls.key` | Secret de type TLS utilisé par l'Ingress |
| `curl -sk https://legeni.local/api/info` | test HTTPS |
| `curl -skv https://legeni.local/ 2>&1 \| grep -E 'subject:\|issuer:'` | affiche le certificat présenté |
| `kubectl apply --dry-run=client -f defi-cert-manager.yaml` | vérifie le YAML du défi sans l'appliquer |

## Résultats obtenus
- Contrôleur `ingress-nginx-controller` **Running**, IngressClass `nginx`.
- Service `webapp` en **ClusterIP** : l'ancien `http://192.168.49.2:30080` ne répond plus.
- Ingress `legeni` : `ADDRESS 192.168.49.2` ; `curl http://legeni.local/api/info` → `{"app":"legeni-webapp","env":"dev",…,"version":"2.0.0"}` **sans numéro de port**.
- `blog.legeni.local` → WordPress (`HTTP/1.1 302 Found` vers la page `WordPress › Installation`) : **deux applications, deux noms, un seul point d'entrée**.
- `describe ingress` : `/api` et `/` → `webapp:80 (10.244.0.63:5000, 10.244.0.64:5000)`.
- **HTTPS** : `curl -k https://legeni.local/api/info` répond ; certificat `subject: CN=legeni.local`, `issuer: CN=legeni.local` (auto-signé) ; sans `-k`, curl refuse le certificat. En HTTP, l'Ingress **redirige automatiquement** vers HTTPS (`308 Permanent Redirect`) dès que le TLS est configuré.
- Défi : `kubectl apply --dry-run` → `no matches for kind "ClusterIssuer"` (cert-manager non installé) : YAML rédigé seulement.

## Réponses aux questions

**Pourquoi l'Ingress plutôt que des NodePort ?** Un NodePort = un port exotique (30000-32767) par application, pas de nom de domaine, pas de HTTPS centralisé. L'Ingress offre **un seul point d'entrée** (ports 80/443), du routage par **nom d'hôte** et par **chemin**, et la terminaison **TLS** au même endroit. Les Services redeviennent internes (ClusterIP).

**Pourquoi l'Ingress `blog` est-il dans le namespace `default` ?** Un Ingress ne peut cibler que des Services **de son propre namespace** : WordPress est dans `default`, la webapp dans `legeni-dev`, donc un Ingress par namespace.

**Défi cert-manager :** on installe cert-manager, on crée un **`ClusterIssuer`** (ACME Let's Encrypt, solveur `http01` via l'Ingress nginx) et on ajoute à l'Ingress l'annotation **`cert-manager.io/cluster-issuer: letsencrypt-prod`** avec une section `tls` (`secretName`). cert-manager crée alors le Secret TLS et **renouvelle** le certificat automatiquement. Il faut un vrai domaine public joignable par Let's Encrypt (impossible avec `legeni.local`).
