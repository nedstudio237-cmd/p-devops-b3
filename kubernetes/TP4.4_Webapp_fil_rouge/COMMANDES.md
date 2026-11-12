# TP 4.4 – Déployer l'application fil rouge sur Kubernetes

**Objectif :** déployer **notre** image `legeni-webapp` dans le cluster, l'exposer sur le port 8180, lui passer sa configuration par variables d'environnement et vérifier la répartition entre réplicas.

**Statut :** ✅ réalisé et vérifié (défi compris) – preuves dans [`preuves/`](preuves/)
**Image utilisée :** `nedstudio/legeni-webapp:1.0.2` – publiée sur Docker Hub par le pipeline Jenkins (option A du TP).

## 🧠 À mémoriser

| Commande | À quoi elle sert |
|---|---|
| `minikube image load image:tag` | copie une image locale dans le nœud Minikube |
| `kubectl rollout status deployment/<nom>` | attend la fin d'un déploiement |
| `curl -s $URL/api/info` | interroge l'application déployée |
| `kubectl rollout undo deployment/<nom>` | revient à la version précédente |
| `kubectl get deploy <nom> -o jsonpath='{.spec.template.spec.containers[0].image}'` | affiche l'image déployée |
| `kubectl describe pod -l app=webapp` | comprend un `ImagePullBackOff` (section Events) |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`webapp-deployment.yaml`](webapp-deployment.yaml) | 2 réplicas, port 5000, `APP_ENV=k8s-dev`, `APP_COLOR=#2da44e` |
| [`webapp-service.yaml`](webapp-service.yaml) | NodePort : port 8180 → conteneur 5000, nodePort 30180 |
| [`webapp-prod.yaml`](webapp-prod.yaml) / [`webapp-prod-svc.yaml`](webapp-prod-svc.yaml) | Défi : 2e instance `webapp-prod` (3 réplicas, `prod`, rouge, nodePort 30181) |

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `minikube image load legeni-webapp:1.0.0` | (option B) copie une image locale dans le nœud Minikube |
| `minikube image ls \| grep legeni` | Liste les images présentes dans le nœud |
| `kubectl apply -f webapp-deployment.yaml -f webapp-service.yaml` | Crée le Deployment et le Service |
| `kubectl rollout status deployment/webapp-deployment` | Attend que le déploiement soit terminé |
| `kubectl get pods -l app=webapp -o wide` | Pods, IP et nœud |
| `URL=$(minikube service webapp-service --url)` | URL d'accès (`http://192.168.49.2:30180`) |
| `curl -s $URL/api/info` | Interroge l'API de l'application (version, env, hostname) |
| `for i in $(seq 1 10); do curl -s $URL/api/info \| python3 -c '…hostname…'; done \| sort \| uniq -c` | Compte les réponses par Pod |
| `kubectl apply -f …` (tag `9.9.9`) | Déploie volontairement une image inexistante |
| `kubectl describe pod -l app=webapp` | Événements du Pod en erreur |
| `kubectl rollout undo deployment/webapp-deployment` | Revient à la version précédente du Deployment |
| `kubectl get deploy webapp-deployment -o jsonpath='{.spec.template.spec.containers[0].image}'` | Affiche l'image actuellement déployée |
| `sed -e 's/…/…/' fichier.yaml > nouveau.yaml` | Défi : dérive un 2e jeu de manifestes (nom, labels, réplicas, env, couleur, port) |
| `git add tp44 && git commit -m "…"` | Versionne les manifestes (la vérité est dans Git) |

## Résultats obtenus
- Déploiement réussi : `{"app":"legeni-webapp","env":"k8s-dev",…,"version":"1.0.2"}`, bannière `#2da44e`.
- Répartition : 4 / 6 réponses sur les 2 Pods.
- Compteur de visites : valeurs qui « sautent » (1, 2, 1, 1, 2, 3…), `Stockage du compteur : memoire`.
- Image `9.9.9` : un nouveau Pod en `ImagePullBackOff`, les **2 anciens restent `Running`** et l'application répond toujours (`version 1.0.2`). `kubectl rollout undo` → retour à `nedstudio/legeni-webapp:1.0.2`. Le fichier YAML, lui, n'a jamais contenu `9.9.9` (copie temporaire).
- Défi : `webapp-prod` répond `"env":"prod"` sur 30181 pendant que `webapp-service` répond `"env":"k8s-dev"` sur 30180.

## Réponses aux questions

**Pourquoi le nombre de visites saute-t-il ?** La page indique `Stockage du compteur : memoire` : chaque processus garde son propre compteur en RAM. Il y a 2 Pods (et dans chaque Pod, 2 workers gunicorn), et le Service envoie chaque requête à un Pod différent : on voit tour à tour des compteurs indépendants. Ils sont aussi perdus au redémarrage. **Solution (TP 4.7)** : un **Redis** partagé (`REDIS_HOST`), configuré par ConfigMap/Secret, qui stocke un compteur unique pour tous les réplicas.

**Pourquoi les anciens Pods n'ont-ils pas été supprimés avec l'image 9.9.9 ?** Le Deployment utilise la stratégie **RollingUpdate** : il crée d'abord un nouveau Pod et ne supprime un ancien que lorsque le nouveau est **prêt**. Le nouveau Pod ne démarrant jamais (`ImagePullBackOff`), le remplacement est bloqué et les anciens Pods continuent de servir : **pas d'interruption de service**.

**Attention à `rollout undo` :** il corrige le **cluster** mais pas le **fichier**. kubectl l'indique d'ailleurs : *« Rolling back will not update the last-applied-configuration annotation… Consider using 'kubectl apply' with your previous configuration file instead »*. En production on revient en arrière par `git revert` + nouveau déploiement.

**Défi : pourquoi changer aussi les labels ?** Si `webapp-prod` gardait `app: webapp`, le Service `webapp-service` sélectionnerait aussi ses Pods (et inversement) : les deux instances seraient mélangées. Le nom **et** le label/selector doivent être différents (la bonne pratique, un namespace par environnement, est vue aux TPs 4.7 et 4.12).
