#!/bin/bash
# boucle.sh URL FICHIER : interroge l'application toutes les 0,5 s et note la version (ou ERREUR)
while true; do
  r=$(curl -s -m1 "$1/api/info") && echo "$(date +%T) $(echo "$r" | sed -E 's/.*"hostname":"([^"]+)".*"version":"([^"]+)".*/v\2 \1/')" || echo "$(date +%T) ❌ ERREUR"
  sleep 0.5
done >> "$2"
