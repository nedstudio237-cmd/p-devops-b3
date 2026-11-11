#!/bin/bash
set -euo pipefail
IMAGE=${DOCKERHUB_ID}/${IMAGE_NAME}
UNIQUE_TAG=$(cat tag.txt)

echo "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USER}" --password-stdin
docker push ${IMAGE}:${UNIQUE_TAG}
# "latest" ne pointe que vers une image qui a passé les tests
docker tag ${IMAGE}:${UNIQUE_TAG} ${IMAGE}:latest
docker push ${IMAGE}:latest
docker logout
echo "Image publiée : ${IMAGE}:${UNIQUE_TAG}"
