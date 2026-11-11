#!/bin/bash
set -euo pipefail                       # arrêter le job à la première erreur

echo "== Build n°${BUILD_NUMBER} du commit ${GIT_COMMIT:0:7} dans ${WORKSPACE}"
echo "Job ${JOB_NAME}, URL ${BUILD_URL}"   # étape 7 : variables d'environnement Jenkins

# Dockerfile généré à partir du code récupéré par Jenkins
cat > Dockerfile <<'EOT'
FROM nginx:1.27-alpine
LABEL maintainer="Legeni"
COPY . /usr/share/nginx/html/
EXPOSE 80
EOT
printf '.git\nDockerfile\n' > .dockerignore

docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -t ${IMAGE_NAME}:build-${BUILD_NUMBER} .
docker images ${IMAGE_NAME}

# Relancer le conteneur : on supprime d'abord celui du build précédent (idempotence)
docker rm -f legeni_website 2>/dev/null || true
docker run --name legeni_website -d -p ${PORT}:80 ${IMAGE_NAME}:${IMAGE_TAG}
docker ps --filter name=legeni_website

# Défi : garder seulement les 3 images build-* les plus récentes
if [ "${NETTOYER}" = "true" ]; then
  docker images ${IMAGE_NAME} --format '{{.Tag}}' | grep '^build-' | sort -t- -k2 -n -r | tail -n +4 \
    | xargs -r -I{} docker rmi ${IMAGE_NAME}:{}
  echo "== Images restantes :"; docker images ${IMAGE_NAME}
fi
