#!/bin/bash
set -euo pipefail
TEST=${IMAGE_NAME}-test
IMAGE=${DOCKERHUB_ID}/${IMAGE_NAME}
UNIQUE_TAG=${IMAGE_TAG}.${BUILD_NUMBER}-${GIT_COMMIT:0:7}     # ex. 1.0.12-3f9c2ab

cat > Dockerfile <<'EOT'
FROM nginx:1.27-alpine
__APK_UPGRADE__
COPY . /usr/share/nginx/html/
EXPOSE 80
EOT
printf '.git\nDockerfile\n' > .dockerignore
docker build --label org.opencontainers.image.revision=${GIT_COMMIT} \
             -t ${IMAGE}:${UNIQUE_TAG} -t ${IMAGE_NAME}:${IMAGE_TAG} .

JENKINS_NET=$(docker inspect jenkins -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')
docker rm -f ${TEST} 2>/dev/null || true
docker run -d --name ${TEST} --network ${JENKINS_NET} ${IMAGE}:${UNIQUE_TAG}
for i in $(seq 1 10); do curl -sf http://${TEST}/ >/dev/null && break; sleep 1; done

echo "${UNIQUE_TAG}" > tag.txt          # transmis à l'étape de publication
