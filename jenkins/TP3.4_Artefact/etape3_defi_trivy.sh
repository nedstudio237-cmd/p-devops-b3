#!/bin/bash
set -euo pipefail
# Défi : refuser de publier si l'image contient une vulnérabilité CRITICAL corrigeable
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy_cache:/root/.cache aquasec/trivy:0.57.1 \
  image --quiet --severity CRITICAL --ignore-unfixed --exit-code 1 \
  ${DOCKERHUB_ID}/${IMAGE_NAME}:$(cat tag.txt)
echo "✅ aucune vulnérabilité CRITICAL corrigeable"
