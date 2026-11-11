#!/bin/bash
set -euo pipefail
docker pull nedstudio/restaurant:latest
docker rm -f restaurant-prod 2>/dev/null || true
docker run -d --name restaurant-prod -p 8099:80 nedstudio/restaurant:latest
docker ps --filter name=restaurant-prod
