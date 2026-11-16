# TP 5.2 – Premier playbook : nginx, templates et handlers

**Objectif :** décrire l'état souhaité d'un serveur web dans un **playbook** versionné, rejouable à l'infini, avec une page générée par **template** et un rechargement du service uniquement quand c'est nécessaire (**handler**).

**Statut :** ✅ réalisé et vérifié (défi compris) – preuves dans [`preuves/`](preuves/)

## 🧠 À mémoriser

| Commande / notion | À quoi ça sert |
|---|---|
| `ansible-playbook nginx.yml` | exécute un playbook |
| `ansible-playbook nginx.yml --syntax-check` | vérifie la syntaxe sans rien exécuter |
| `ansible-playbook nginx.yml --check --diff` | « dry run » : montre ce qui serait modifié, ligne par ligne |
| `--limit web1` | n'exécute que sur certains serveurs |
| `PLAY RECAP … changed=0` | 2ᵉ passage sans modification = playbook **idempotent** |
| `template` + `{{ variable }}` / `{% if %}` / `{% for %}` | fichier généré avec Jinja2 à partir des variables et des facts |
| `notify` + `handlers` | action exécutée **une seule fois, à la fin**, et seulement si une tâche a changé |
| `meta: flush_handlers` | exécute les handlers en attente tout de suite |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`../lab/nginx.yml`](../lab/nginx.yml) | Playbook : installer nginx, publier la page (template), démarrer le service, handler `Recharger nginx` + **défi** (page de statut 8090, `nginx -t`, `flush_handlers`, vérification `uri`) |
| [`../lab/templates/index.html.j2`](../lab/templates/index.html.j2) | Template Jinja2 (pied de page modifié à l'étape 4) |

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `cat nginx.yml` | lecture du playbook : play, `hosts`, `become`, `tasks`, `handlers`, `notify` |
| `ansible-playbook nginx.yml --syntax-check` | erreurs de syntaxe YAML / Ansible |
| `ansible-playbook nginx.yml --list-tasks` | liste des tâches qui seront exécutées |
| `ansible-playbook nginx.yml --check` | simulation (peut échouer la 1ʳᵉ fois : le paquet n'est pas réellement installé) |
| `ansible-playbook nginx.yml` (x2) | 1ᵉʳ passage : changements + handler ; 2ᵉ : `changed=0` |
| `curl -s localhost:8001` / `:8002` | pages générées sur web1 / web2 |
| `ansible-playbook nginx.yml --diff` | affiche les lignes modifiées dans les fichiers |
| `ansible-playbook nginx.yml --check --diff --limit web1` | simulation sur un seul serveur |
| `ansible web1 -b -m shell -a "echo PIRATE > /var/www/html/index.html"` | simule une modification manuelle (dérive) |
| `ansible.builtin.command: nginx -t` + `changed_when: false` | défi : valide la config sans marquer la tâche « changée » |
| `ansible.builtin.uri: url=… status_code=200` | défi : test HTTP depuis le serveur |

## Résultats obtenus
- `--syntax-check` OK ; `--list-tasks` liste les 3 tâches ; `--check` échoue sur le service (`Could not find the requested service nginx`), comme annoncé par le TP.
- **1ᵉʳ passage** : `ok=5 changed=4` par serveur, `RUNNING HANDLER [Recharger nginx]`.
- **2ᵉ passage** : `ok=4 changed=0`, pas de handler → **idempotent**.
- Pages : web1 → `Legeni – serveurs web`, Ubuntu 24.04, 7889 Mo, 4 CPU, équipe Alice/Bob ; web2 → `Legeni – web2 (canari)` (variable d'hôte prioritaire sur la variable de groupe).
- Pied de page modifié → `--diff` montre la ligne `-`/`+`, seule la tâche *Publier la page* est `changed`, puis le handler.
- `--check --diff --limit web1` après coup : `changed=0`.
- **Dérive** : page remplacée par `PIRATE` → `ansible-playbook --diff` montre `-PIRATE` / `+ <h1>Legeni – serveurs web</h1>` → page restaurée.
- **Défi** : 1ᵉʳ passage `changed=2` (fichier `status.conf` + handler) ; `nginx -t` OK ; `/nginx_status` → `Active connections: 1` ; 2ᵉ passage `changed=0`.

## Réponses / à retenir
- **Play** = « sur quels serveurs (`hosts: web`), avec quels droits (`become: true`), quelles tâches ». **Tâche** = un module + ses paramètres. **Handler** = tâche déclenchée par `notify`, exécutée une fois à la fin du play et **seulement si** la tâche qui notifie a changé (on ne recharge pas nginx pour rien).
- **Template** : `{{ inventory_hostname }}` (nom dans l'inventaire), `{{ ansible_facts['memtotal_mb'] }}` (fact), `{% if equipe is defined %}…{% for %}` (logique), `| default('…')` (valeur par défaut).
- **Infrastructure as Code** : le playbook dans Git est la référence ; toute modification manuelle (dérive) est détectée (`--check --diff`) et corrigée par une simple ré-exécution.
