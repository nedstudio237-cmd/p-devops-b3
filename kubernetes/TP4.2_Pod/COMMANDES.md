# TP 4.2 – Le Pod : commandes utilisées

**Objectif du TP :** créer un Pod à partir d'un fichier YAML, l'interroger, y entrer, lire ses événements, et constater qu'un Pod seul **n'est pas résilient** (d'où le Deployment du TP 4.3).

**Statut :** ✅ réalisé et vérifié – preuves dans [`preuves/`](preuves/)

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`pod.yaml`](pod.yaml) | Pod `my-pod` (nginx:1.27-alpine), labels `app=myapp`, `tier=front`, `env=dev` |
| [`pod-sidecar.yaml`](pod-sidecar.yaml) | Pod à 2 conteneurs (nginx + busybox) partageant un volume `emptyDir` |
| [`redis-pod.yaml`](redis-pod.yaml) | Défi : manifeste généré par `kubectl run --dry-run=client -o yaml` |

## Commandes et rôle

### Créer / modifier / supprimer
| Commande | Rôle |
|---|---|
| `kubectl apply -f pod.yaml` | Crée ou met à jour l'objet décrit dans le fichier (`created` / `configured` / `unchanged`) |
| `kubectl apply -f pod.yaml --dry-run=server` | Fait valider le fichier par l'API **sans rien créer** |
| `kubectl delete -f pod.yaml` | Supprime les objets décrits dans le fichier |
| `kubectl delete pod my-pod` | Supprime un Pod par son nom |

### Observer
| Commande | Rôle |
|---|---|
| `kubectl get pods` | Liste les Pods (état, READY, RESTARTS, âge) |
| `kubectl get pods -w` | Suit les changements d'état en direct (Ctrl+C pour sortir) |
| `kubectl get pod my-pod -o wide` | Ajoute l'IP du Pod et le nœud |
| `kubectl get pod my-pod -o yaml` | Objet complet : `spec` (voulu) + `status` (réel) |
| `kubectl describe pod my-pod` | Détail + **Events** : outil de diagnostic n°1 |
| `kubectl explain pod.spec.containers.ports` | Documentation intégrée d'un champ |

### Interagir
| Commande | Rôle |
|---|---|
| `kubectl logs my-pod` | Sortie standard du conteneur |
| `kubectl logs web-sidecar -c generateur` | Logs d'un conteneur précis d'un Pod multi-conteneurs |
| `kubectl exec -it my-pod -- sh` | Shell interactif dans le conteneur |
| `kubectl exec my-pod -- sh -c 'kill 1'` | Lance une commande dans le conteneur (ici : tuer le processus principal) |
| `kubectl port-forward pod/my-pod 8085:80` | Tunnel poste → Pod pour tester (8085 car 8080 = Jenkins) |

### Labels et sélecteurs
| Commande | Rôle |
|---|---|
| `kubectl get pods --show-labels` | Affiche les labels |
| `kubectl get pods -l app=myapp` | Filtre par label |
| `kubectl get pods -l 'env in (dev,staging)'` | Filtre sur un ensemble de valeurs |
| `kubectl get pods -L app,env` | Labels en colonnes |
| `kubectl label pod my-pod env=dev` | Ajoute un label dans le cluster (pas dans le fichier) |

### Générer / attendre
| Commande | Rôle |
|---|---|
| `kubectl run redis --image=redis:7.4-alpine --labels=app=cache --dry-run=client -o yaml > redis-pod.yaml` | Génère un manifeste sans l'écrire à la main |
| `kubectl wait --for=condition=Ready pod/redis --timeout=60s` | Attend que le Pod soit prêt avant de continuer |

## Réponses aux questions

**1. Composants visibles dans les Events (`From`) :** `default-scheduler` (choisit le nœud du Pod) et `kubelet` (agent du nœud : télécharge l'image, crée et démarre le conteneur). En amont, l'API server reçoit la demande et etcd la stocke.

**2. Champs ajoutés dans `-o yaml` :** `uid`, `creationTimestamp`, `resourceVersion`, `restartPolicy: Always`, `imagePullPolicy`, `nodeName`, et toute la section `status` (IP, conditions…). Ajoutés par l'API server (valeurs par défaut), le scheduler (`nodeName`) et le kubelet (`status`).

**3. Les conteneurs d'un Pod partagent-ils l'IP ?** Oui : `kubectl exec web-sidecar -c generateur -- wget -qO- localhost` (busybox, sans serveur web) renvoie la page de nginx. Ils partagent le réseau (une seule IP, même `localhost`) et les volumes.

## À retenir
1. **Déclaratif** : on décrit l'état voulu dans un YAML, qui est la source de vérité.
2. **Labels** : les objets se trouvent par étiquettes, pas par nom.
3. **Un Pod seul n'est pas résilient** : le kubelet redémarre un conteneur qui plante (`RESTARTS 1`), mais personne ne recrée un Pod supprimé → c'est le rôle du **Deployment**.
4. `kubectl apply` rend la main **avant** que le Pod soit prêt → `kubectl wait`.
