#!/bin/bash
# Suit le build de main : attend la validation, mesure la prod en continu, valide (« Déployer »), affiche le résultat.
#   deploy-main.sh <fichier_boucle> [abort]
set -uo pipefail
OUT=$1; MODE=${2:-deploy}
U=$(sed -n 1p ~/.secrets/jenkins); T=$(sed -n 2p ~/.secrets/jenkins); JM=http://localhost:8080/job/legeni-webapp-mb/job/main
api() { curl -s -u "$U:$T" "$@"; }
PREV=$(api "$JM/lastBuild/api/json?tree=number" | grep -oE '[0-9]+$|[0-9]+}' | tr -d })
api -X POST "http://localhost:8080/job/legeni-webapp-mb/build?delay=0" -o /dev/null
until N=$(api "$JM/lastBuild/api/json?tree=number" | grep -oE '[0-9]+$|[0-9]+}' | tr -d }); [ "$N" -gt "$PREV" ]; do sleep 5; done
echo "build main #$N"
while ! api "$JM/$N/consoleText" | grep -q "en production ?"; do
  api "$JM/$N/api/json?tree=building" | grep -q '"building":false' && { echo "terminé avant la validation"; api "$JM/$N/api/json?tree=result"; exit 0; }
  sleep 5; done
api "$JM/$N/consoleText" | grep -E "staging OK" | sed 's/.*msg/msg/'
IP=$(minikube ip)
( for i in $(seq 1 600); do r=$(curl -s -m 2 $IP:30082/api/info | grep -oE '"version":"[^"]+"' || echo ERREUR); echo "$(date +%T) $r"; sleep 0.3; done > "$OUT" ) &
LOOP=$!
sleep 3
ID=$(api $JM/$N/wfapi/pendingInputActions | grep -oE '"id":"[^"]+"' | cut -d'"' -f4)
api -X POST "$JM/$N/input/$ID/proceedEmpty" -o /dev/null
until api "$JM/$N/api/json?tree=building" | grep -q '"building":false'; do sleep 3; done
sleep 10; kill $LOOP 2>/dev/null; wait $LOOP 2>/dev/null
api "$JM/$N/api/json?tree=result" | grep -oE '"result":"[A-Z]+"'
api "$JM/$N/consoleText" | grep -E "prod OK|rollback effectué|Retour à la version|new tag|déjà présent" | sed 's/.*msg/msg/'
echo "requêtes prod: $(wc -l < "$OUT"), erreurs: $(grep -c ERREUR "$OUT")"; cut -d' ' -f2 "$OUT" | uniq -c | awk '{print $2, $1}' | uniq | head -5
echo "$N" > /tmp/claude-1000/-home-romaric/c62b2ef9-ed79-4c30-afb9-0e4a8ee8c794/scratchpad/lastmain
