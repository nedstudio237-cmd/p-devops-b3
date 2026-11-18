#!/bin/bash
# Cycle « pull request » utilisé pour le projet : ouvre la PR, attend le build Jenkins de la PR, fusionne.
#   pr.sh <branche> "<titre>"            (la branche doit être poussée)
set -euo pipefail
BR=$1; TITLE=$2; REPO=nedstudio237-cmd/legeni-webapp
TOKEN=$(sed -nE 's#https://[^:]+:([^@]+)@github.com#\1#p' ~/.git-credentials | head -1)
U=$(sed -n 1p ~/.secrets/jenkins); T=$(sed -n 2p ~/.secrets/jenkins); JK=http://localhost:8080/job/legeni-webapp-mb
gh() { curl -s -H "Authorization: Bearer $TOKEN" "$@"; }
# PR déjà ouverte pour cette branche ? sinon on la crée
RESP=$(gh "https://api.github.com/repos/$REPO/pulls?state=open&head=${REPO%%/*}:$BR")
echo "$RESP" | grep -q '"number"' || RESP=$(gh https://api.github.com/repos/$REPO/pulls -d "{\"title\":\"$TITLE\",\"head\":\"$BR\",\"base\":\"main\",\"body\":\"🤖 Generated with [Claude Code](https://claude.com/claude-code)\"}")
N=$(echo "$RESP" | grep '"number"' | head -1 | grep -oE '[0-9]+')
echo "PR #$N ouverte"
curl -s -u "$U:$T" -X POST "$JK/build?delay=0" -o /dev/null
until curl -sf -u "$U:$T" "$JK/job/PR-$N/1/api/json?tree=building" 2>/dev/null | grep -q '"building":false'; do sleep 5; done
R=$(curl -s -u "$U:$T" "$JK/job/PR-$N/1/api/json?tree=result" | grep -oE '"result":"[A-Z]+"' | cut -d'"' -f4)
echo "build PR-$N : $R"
[ "$R" = SUCCESS ] || exit 1
sleep 3
M=$(gh -X PUT https://api.github.com/repos/$REPO/pulls/$N/merge -d '{"merge_method":"merge"}'); echo "$M" | grep '"message"'
gh -X DELETE https://api.github.com/repos/$REPO/git/refs/heads/$BR -o /dev/null
cd ~/legeni-webapp && git checkout -q main && git pull -q && git branch -qD "$BR" && git fetch -q --prune
echo "main local à jour : $(git log --oneline -1)"
