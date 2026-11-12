# TP 4.3 – Deployment, ReplicaSet et Service

**Objectif :** déployer une application en plusieurs **réplicas** avec un Deployment, observer l'**auto-réparation**, puis l'exposer par un **Service** qui répartit la charge entre les Pods.

**Statut :** ✅ réalisé et vérifié (défi compris) – preuves dans [`preuves/`](preuves/)

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`deployment.yaml`](deployment.yaml) | Deployment `my-deployment` : 3 réplicas nginx, selector `app: myapp` |
| [`service.yaml`](service.yaml) | Service `my-service` NodePort 30080 → Pods `app: myapp` |
| [`echo.yaml`](echo.yaml) | Défi : `http-echo` 2 réplicas + Service ClusterIP `echo` |

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `kubectl apply -f deployment.yaml` | Crée le Deployment (qui crée un ReplicaSet, qui crée les Pods) |
| `kubectl get deploy,rs,pods -l app=myapp` | Montre la chaîne Deployment → ReplicaSet → Pods |
| `kubectl get pods -l app=myapp -w` | Suit en direct la création/suppression des Pods |
| `kubectl delete pod -l app=myapp --wait=false` | Supprime tous les Pods d'un coup (test d'auto-réparation) |
| `kubectl describe rs -l app=myapp \| grep -A5 Events` | Événements du ReplicaSet : qui a recréé les Pods |
| `kubectl scale deployment my-deployment --replicas=5` | Change le nombre de réplicas (impératif) |
| `kubectl apply -f deployment.yaml` (avec `replicas: 3`) | Même chose de façon déclarative (fichier versionné) |
| `kubectl apply -f service.yaml` | Crée le Service |
| `kubectl get svc my-service` | Type, ClusterIP, ports du Service |
| `kubectl get endpointslices -l kubernetes.io/service-name=my-service` | IP des Pods derrière le Service |
| `minikube service my-service --url` | URL d'accès depuis la machine (`http://192.168.49.2:30080`) |
| `kubectl exec $p -- sh -c 'echo "Servi par $(hostname)" > …/index.html'` | Personnalise la page de chaque Pod pour voir qui répond |
| `for i in $(seq 1 30); do curl -s $URL; done \| sort \| uniq -c` | Compte les réponses par Pod (répartition de charge) |
| `kubectl run client --rm -i --image=busybox:1.36 --restart=Never -- wget -qO- my-service` | Pod jetable pour tester le Service depuis l'intérieur du cluster |
| `nslookup my-service` | Résolution DNS interne du nom du Service |
| `kubectl patch svc my-service -p '{"spec":{"type":"ClusterIP"}}'` | Modifie un champ à chaud (ici le type de Service) |
| `kubectl delete -f service.yaml -f deployment.yaml` | Nettoyage |

## Résultats obtenus
- `kubectl get deploy,rs,pods` : Deployment `3/3`, ReplicaSet `my-deployment-7cd6b456c4`, 3 Pods `my-deployment-7cd6b456c4-xxxxx`.
- Label du template ≠ selector → refusé : `` `selector` does not match template `labels` ``.
- Suppression des 3 Pods → 3 nouveaux Pods aussitôt (`replicaset-controller  Created pod: …`).
- Scaling 5 → 2 → retour à 3 par `kubectl apply`.
- 3 adresses dans l'EndpointSlice ; 30 requêtes réparties **9 / 11 / 10** sur les 3 Pods.
- DNS : `my-service` et `my-service.default.svc.cluster.local` répondent ; `nslookup` → `10.104.130.200`.
- Passage en ClusterIP : plus de port 30080, `inaccessible depuis l'extérieur` ; `kubectl apply -f service.yaml` remet le NodePort.
- Défi : `wget -qO- echo` depuis un Pod jetable → `version bleue`.

## Réponses aux questions

**À quoi correspond le hash dans le nom des Pods ? Quel objet intermédiaire ?** Le Deployment crée un **ReplicaSet** nommé `my-deployment-<hash>` ; le hash (`7cd6b456c4`) est calculé à partir du **template** des Pods. Chaque version du template = un nouveau ReplicaSet (c'est ce qui permet le rolling update et le rollback, TP 4.8). Les Pods portent le nom du ReplicaSet + un suffixe aléatoire.

**Qui a recréé les Pods (comparé au TP 4.2) ?** Le **contrôleur ReplicaSet** du `kube-controller-manager` : il compare en boucle l'état désiré (3 réplicas) à l'état réel (0 Pod) et recrée la différence. Au TP 4.2, un Pod seul n'avait aucun contrôleur, donc personne ne le recréait.

**Pourquoi le déclaratif est-il préférable en équipe ?** Le fichier YAML dans Git est la source de vérité : relu, historisé, reproductible. Si un collègue fait `kubectl scale` à la main, le changement n'est écrit nulle part, et au prochain `kubectl apply -f deployment.yaml` le nombre de réplicas **revient à la valeur du fichier** : sa modification est écrasée sans prévenir.

**Types de Service :**

| Type | Accessible depuis | Usage typique |
|---|---|---|
| `ClusterIP` (défaut) | uniquement l'intérieur du cluster | communication interne entre services (API ↔ base de données) |
| `NodePort` | l'extérieur, via `IP_du_nœud:30000-32767` | tests, environnements simples, accès direct sans load balancer |
| `LoadBalancer` | l'extérieur, via une IP publique fournie par le cloud (`minikube tunnel` en local) | exposer un service en production chez un fournisseur cloud |
| Ingress (pas un type de Service) | l'extérieur, en HTTP/HTTPS, par **nom de domaine / chemin** | plusieurs applications web derrière un seul point d'entrée, TLS |
