#!/bin/bash
set -euo pipefail
TEMPS=$(for i in $(seq 1 10); do curl -s -o /dev/null -w '%{time_total}\n' http://${IMAGE_NAME}-test/; done)
MOY=$(echo "$TEMPS" | awk '{s+=$1} END {printf "%.3f", s/NR}')
echo "Temps moyen : ${MOY} s"
awk -v m="$MOY" 'BEGIN { exit !(m < 0.5) }' || { echo "❌ trop lent"; exit 1; }
echo "✅ performance OK (< 0,5 s)"
