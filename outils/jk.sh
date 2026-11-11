#!/bin/bash
# Petit client de l'API Jenkins utilisé pour réaliser les TPs.
# Identifiants lus dans ~/.secrets/jenkins (ligne 1 : utilisateur, ligne 2 : jeton d'API).
#   jk.sh create <job> <config.xml>      créer (ou remplacer) un job
#   jk.sh build  <job> [PARAM=val ...]   lancer un build, attendre la fin, afficher le résultat
#   jk.sh console <job> [n]              console du build n (dernier par défaut)
#   jk.sh config <job>                   exporter la configuration XML d'un job
set -euo pipefail
JENKINS=${JENKINS_URL:-http://localhost:8080}
U=$(sed -n 1p ~/.secrets/jenkins); T=$(sed -n 2p ~/.secrets/jenkins)
api() { curl -sf -u "$U:$T" "$@"; }
cmd=$1; job=${2:-}; shift 2 || true
jobpath=$(echo "$job" | sed 's#/#/job/#g')
case $cmd in
  create)
    if api -o /dev/null "$JENKINS/job/$jobpath/config.xml"; then
      api -X POST -H 'Content-Type: application/xml' --data-binary @"$1" "$JENKINS/job/$jobpath/config.xml"
    else
      api -X POST -H 'Content-Type: application/xml' --data-binary @"$1" "$JENKINS/createItem?name=$job"
    fi
    echo "job $job prêt" ;;
  build)
    next=$(api "$JENKINS/job/$jobpath/api/json?tree=nextBuildNumber" | sed -E 's/.*"nextBuildNumber":([0-9]+).*/\1/')
    if [ $# -gt 0 ]; then
      args=(); for p in "$@"; do args+=(--data-urlencode "$p"); done
      api -X POST "${args[@]}" "$JENKINS/job/$jobpath/buildWithParameters" -o /dev/null
    else
      api -X POST "$JENKINS/job/$jobpath/build" -o /dev/null
    fi
    until api -o /dev/null "$JENKINS/job/$jobpath/$next/api/json"; do sleep 2; done
    while api "$JENKINS/job/$jobpath/$next/api/json?tree=building" | grep -q '"building":true'; do sleep 3; done
    res=$(api "$JENKINS/job/$jobpath/$next/api/json?tree=result" | sed -E 's/.*"result":"?([A-Z_a-z]+)"?.*/\1/')
    echo "build #$next : $res" ;;
  console)
    n=${1:-lastBuild}; api "$JENKINS/job/$jobpath/$n/consoleText" ;;
  config)
    api "$JENKINS/job/$jobpath/config.xml" ;;
  *) echo "usage: $0 create|build|console|config <job> ..." >&2; exit 1 ;;
esac
