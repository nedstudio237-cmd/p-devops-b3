#!/bin/bash
# Prépare l'environnement avant la présentation des TPs (à lancer 10 min avant).
#   bash ~/tp-devops-b3/outils/preparer-demo.sh
set -u
ok()  { echo "  ✅ $*"; }
ko()  { echo "  ❌ $*"; }

echo "== 1. Minikube"
minikube status >/dev/null 2>&1 || minikube start
kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready" && ok "cluster Kubernetes prêt" || ko "cluster non prêt"

echo "== 2. Jenkins + Ansible (après Minikube : réseau minikube)"
(cd ~/devops-tp && docker compose up -d >/dev/null 2>&1)
for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code}" localhost:8080/login | grep -q 200 && break; sleep 3; done
curl -s -o /dev/null -w "%{http_code}" localhost:8080/login | grep -q 200 && ok "Jenkins : http://localhost:8080" || ko "Jenkins ne répond pas"

echo "== 3. Application sur Kubernetes (namespace legeni-dev)"
kubectl -n legeni-dev rollout status deploy/webapp --timeout=120s >/dev/null 2>&1 && ok "webapp : $(minikube service webapp -n legeni-dev --url 2>/dev/null)" || ko "webapp absente (voir TP 4.7)"

echo "== 4. Liens utiles"
echo "  Jenkins ................ http://localhost:8080"
echo "  Site restaurant (3.2) .. http://localhost:8092   (après un build du job 'build')"
echo "  Prod locale (3.4) ...... http://localhost:8099   (après un build du job 'artefact')"
echo "  Webapp K8s (4.7/4.8) ... $(minikube service webapp -n legeni-dev --url 2>/dev/null)"
echo "  Dépôt des TPs .......... https://github.com/nedstudio237-cmd/p-devops-b3"
echo "  Dépôt de l'appli ....... https://github.com/nedstudio237-cmd/legeni-webapp"
echo "  Images Docker Hub ...... https://hub.docker.com/u/nedstudio"
echo "  Dashboard Kubernetes ... lancer dans un autre terminal : minikube dashboard"
