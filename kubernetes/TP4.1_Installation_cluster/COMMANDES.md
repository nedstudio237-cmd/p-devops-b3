# TP 4.1 – Installation d'un cluster Kubernetes (Minikube) et premiers pas

**Objectif :** disposer d'un cluster Kubernetes mono-nœud fonctionnel, savoir l'interroger et l'explorer avant d'y déployer quoi que ce soit.

**Statut :** ✅ réalisé et vérifié – preuves dans [`preuves/`](preuves/)

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`hello.yaml`](hello.yaml) | Squelette YAML d'un Deployment généré avec `--dry-run=client -o yaml` |

> Adaptation : la VM n'a que 7,7 Go de RAM (Jenkins et Ansible tournent aussi) : Minikube est lancé avec `--memory=2200 --cpus=2` au lieu de 4096 Mo.

## Commandes et rôle

### Installation et démarrage
| Commande | Rôle |
|---|---|
| `curl -LO https://dl.k8s.io/release/…/kubectl` + `sudo install … /usr/local/bin/kubectl` | Installe le client Kubernetes |
| `curl -LO …/minikube-linux-amd64` + `sudo install … /usr/local/bin/minikube` | Installe Minikube |
| `kubectl version --client` / `minikube version` | Vérifie les versions installées |
| `minikube start --driver=docker --cpus=2 --memory=2200` | Crée et démarre le cluster dans un conteneur Docker (jamais avec `sudo`) |
| `minikube status` | État du nœud, du kubelet et de l'API server |

### Explorer le cluster
| Commande | Rôle |
|---|---|
| `kubectl cluster-info` | Adresse de l'API server et de CoreDNS |
| `kubectl get nodes -o wide` | Nœuds avec IP, OS et runtime de conteneurs |
| `kubectl get namespaces` | Espaces de noms (default, kube-system…) |
| `kubectl get pods -A` | Tous les Pods de tous les namespaces (le plan de contrôle tourne dans des Pods) |
| `kubectl api-resources` | Tous les types d'objets disponibles |
| `kubectl explain deployment.spec.replicas` | Documentation intégrée d'un champ |

### Modules complémentaires
| Commande | Rôle |
|---|---|
| `minikube addons list` | Liste des modules et leur état |
| `minikube addons enable metrics-server` | Collecte CPU/RAM → `kubectl top`, autoscaling (TP 4.8) |
| `minikube addons enable ingress` | Contrôleur Ingress NGINX (TP 4.11) |
| `minikube addons enable dashboard` | Interface web du cluster |
| `kubectl top nodes` / `kubectl top pods -A` | Consommation CPU/RAM |
| `minikube dashboard --url` | URL du tableau de bord |

### Contexte kubectl
| Commande | Rôle |
|---|---|
| `kubectl config get-contexts` | Clusters connus de kubectl (`~/.kube/config`) |
| `kubectl config current-context` | Cluster actuellement piloté (`minikube`) |
| `kubectl config view --flatten --minify` | Fichier de connexion autonome (à donner à Jenkins au projet final) |

### Premier déploiement impératif
| Commande | Rôle |
|---|---|
| `kubectl create deployment hello --image=nginx:1.27-alpine` | Crée un Deployment en ligne de commande |
| `kubectl expose deployment hello --port=80 --type=NodePort` | Crée un Service qui l'expose sur un port du nœud |
| `kubectl get deploy,rs,pods,svc -l app=hello` | Montre la chaîne Deployment → ReplicaSet → Pod + Service |
| `minikube service hello --url` | URL d'accès au Service depuis la machine |
| `kubectl delete deployment,service hello` | Supprime les objets |
| `kubectl create deployment hello … --dry-run=client -o yaml > hello.yaml` | Génère le YAML sans rien créer |

## Résultats obtenus
- Nœud `minikube` **Ready**, Kubernetes v1.37.0.
- Modules `metrics-server`, `ingress`, `dashboard` activés ; `ingress-nginx-controller` **Running** ; `kubectl top nodes` → 766m CPU (19 %), 751 Mi RAM.
- Déploiement impératif `hello` : `1/1` disponible, page `Welcome to nginx!` via `minikube service hello --url`, puis supprimé.

## Réponses aux questions

**1. Composants du plan de contrôle (`kubectl get pods -n kube-system`) :**

| Pod | Composant | Rôle |
|---|---|---|
| `kube-apiserver-minikube` | API server | Point d'entrée unique du cluster : reçoit les requêtes (`kubectl`), valide, enregistre dans etcd |
| `etcd-minikube` | etcd | Base clé/valeur qui stocke **tout** l'état du cluster |
| `kube-scheduler-minikube` | Scheduler | Choisit sur quel nœud placer chaque nouveau Pod |
| `kube-controller-manager-minikube` | Controller manager | Boucles de contrôle (ReplicaSet, Deployment, nœuds…) qui ramènent l'état réel vers l'état voulu |
| `kube-proxy-55s5m` | kube-proxy | Sur chaque nœud : règles réseau qui implémentent les Services |
| `coredns-…` | CoreDNS | DNS interne : résout les noms des Services (`mon-service.mon-namespace`) |
| `kindnet-…` | CNI | Réseau des Pods (une IP par Pod) |
| `metrics-server-…` | Metrics server | Mesure CPU/RAM pour `kubectl top` et l'autoscaling |
| `storage-provisioner` | Provisionneur | Crée les volumes persistants à la demande |

**2. IP du nœud et runtime :** IP interne **192.168.49.2** ; OS Debian 12 ; runtime **containerd://2.3.4** (et non Docker : Kubernetes parle au runtime via l'interface CRI).

## À retenir
- Le plan de contrôle Kubernetes **tourne lui-même dans des Pods** (namespace `kube-system`).
- Les commandes impératives (`create`, `expose`) ne laissent **aucune trace versionnée** → à partir du TP 4.2 tout est en YAML (`kubectl apply -f`).
