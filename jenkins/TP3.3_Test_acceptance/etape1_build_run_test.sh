#!/bin/bash
set -euo pipefail
TEST=${IMAGE_NAME}-test

cat > Dockerfile <<'EOT'
FROM nginx:1.27-alpine
COPY . /usr/share/nginx/html/
EXPOSE 80
EOT
printf '.git\nDockerfile\n' > .dockerignore
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .

# Jenkins tourne lui-même dans un conteneur : pour qu'il joigne le conteneur de test
# par son nom, on place ce dernier sur le même réseau Docker que Jenkins.
JENKINS_NET=$(docker inspect jenkins -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')
echo "Réseau de Jenkins : ${JENKINS_NET}"
docker rm -f ${TEST} 2>/dev/null || true
docker run -d --name ${TEST} --network ${JENKINS_NET} ${IMAGE_NAME}:${IMAGE_TAG}

# Attendre que nginx accepte les connexions (au plus 10 s)
for i in $(seq 1 10); do curl -sf http://${TEST}/ >/dev/null && break; sleep 1; done
