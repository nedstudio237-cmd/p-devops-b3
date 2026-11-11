#!/bin/bash
set -euo pipefail
TEST=${IMAGE_NAME}-test
# 1. La page d'accueil contient le titre attendu
curl -sf http://${TEST}/ | grep -qi "<title>Restaurant" && echo "✅ titre OK"
# 2. Les ressources statiques sont servies
curl -sf -o /dev/null -w "%{http_code} %{content_type}\n" http://${TEST}/1.jpg
# 3. Une page inexistante renvoie bien 404 (le serveur ne masque pas les erreurs)
test "$(curl -s -o /dev/null -w '%{http_code}' http://${TEST}/nexiste-pas)" = "404" && echo "✅ 404 OK"
