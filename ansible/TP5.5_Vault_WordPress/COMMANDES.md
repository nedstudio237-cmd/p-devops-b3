# TP 5.5 – Secrets avec Ansible Vault : déploiement de WordPress

**Objectif :** déployer WordPress + MariaDB avec un Docker Compose **généré par Ansible**, sans jamais stocker un mot de passe en clair dans Git.

**Statut :** ✅ réalisé et vérifié (défi compris) – preuves dans [`preuves/`](preuves/)

## 🧠 À mémoriser

| Commande | À quoi elle sert |
|---|---|
| `ansible-vault encrypt fichier.yml` | chiffre un fichier de variables (AES256) |
| `ansible-vault view fichier.yml` | affiche le contenu déchiffré |
| `ansible-vault edit fichier.yml` | modifie le fichier sans jamais l'écrire en clair sur le disque |
| `ansible-vault rekey fichier.yml` | change le mot de passe Vault |
| `ansible-vault encrypt_string 'secret' --name 'var'` | chiffre une seule variable (à coller dans un YAML) |
| `ansible-playbook … --ask-vault-pass` | demande le mot de passe Vault au lancement |
| `ansible-playbook … --vault-password-file .vault_pass` | mot de passe dans un fichier (automatisation, Jenkins), **jamais commité** |
| `no_log: true` | empêche une tâche d'afficher des secrets dans les logs |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`../lab/wordpress.yml`](../lab/wordpress.yml) | Playbook : `assert` sur la longueur des mots de passe, rôle `docker` réutilisé, compose généré (`0600`), stack démarrée, attente de WordPress + **défi** sauvegarde |
| [`../lab/vars/wordpress.yml`](../lab/vars/wordpress.yml) | Variables **non sensibles** (dossier, port, base, utilisateur) – en clair |
| [`../lab/vars/wordpress_secrets.yml`](../lab/vars/wordpress_secrets.yml) | Mots de passe **chiffrés** (`$ANSIBLE_VAULT;1.1;AES256`) – peut être commité |
| [`../lab/templates/wordpress-compose.yml.j2`](../lab/templates/wordpress-compose.yml.j2) | Template Docker Compose (MariaDB 11.4 + WordPress 6) |

Le mot de passe Vault est dans `lab/.vault_pass` (droits `600`, **ignoré par Git**) et dans `~/.secrets/vault_pass`.

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `cat ../vars.yml` | le problème : mots de passe en clair dans le fichier historique du cours |
| `cp vars/wordpress_secrets.yml.exemple vars/wordpress_secrets.yml` | fichier de secrets à remplir (ici : mots de passe aléatoires `openssl rand -hex 12`) |
| `ansible-vault encrypt vars/wordpress_secrets.yml` | chiffrement |
| `head -3 vars/wordpress_secrets.yml` | vérifie l'en-tête `$ANSIBLE_VAULT;1.1;AES256` |
| `ansible-playbook wordpress.yml --vault-password-file .vault_pass` | déploie (déchiffrement en mémoire) |
| `ansible-playbook wordpress.yml … -e mysql_password=court` | vérifie que l'`assert` refuse un mot de passe faible |
| `ansible db1 -b -m shell -a "{% raw %}docker inspect wordpress-db-1 --format '{{.Created}}'{% endraw %}"` | date de création du conteneur (`{% raw %}` : empêche Ansible d'interpréter les `{{ }}` de Docker) |
| `ansible db1 -b -m command -a "stat -c '%a %U' /opt/wordpress/docker-compose.yml"` | droits du fichier généré (`600 root`) |
| `ansible-playbook … -v \| grep -c <mot de passe>` | vérifie qu'aucun secret n'apparaît dans les logs |
| `community.docker.docker_container_exec` + `mariadb-dump` | défi : sauvegarde de la base dans le conteneur |
| `ansible.builtin.find` + `sort(attribute='mtime', reverse=true))[5:]` | défi : ne garder que les 5 sauvegardes les plus récentes |

## Résultats obtenus
- `vars/wordpress_secrets.yml` commence par **`$ANSIBLE_VAULT;1.1;AES256`** ; `ansible-vault view` le déchiffre ; `encrypt_string` produit un bloc `api_token: !vault |`.
- 1ᵉʳ déploiement : Docker installé sur db1 par le rôle `docker`, stack MariaDB + WordPress démarrée, **`failed=0`** ; `http://localhost:8103` → assistant d'installation WordPress (HTTP 200).
- `-e mysql_password=court` → **refusé** : `Mots de passe absents ou trop courts (12 caractères minimum)`, `failed=1` avant toute modification.
- Les vrais mots de passe apparaissent **0 fois** dans la sortie verbeuse (`aucune fuite`) ; `docker-compose.yml` en **`600 root`** ; `.vault_pass` ignoré par Git.
- **Faux positif d'idempotence** confirmé : la tâche *Démarrer la stack WordPress* reste `changed` à chaque passage, alors que la date de création du conteneur MariaDB ne change pas (`2026-11-16T03:02:07Z` avant et après) – comportement de `community.docker` 3.7.0 (Ubuntu 24.04).
- **Défi** : 6 déploiements → à chaque fois une sauvegarde `wordpress_<date>.sql` (`0600`), au 6ᵉ la plus ancienne est supprimée : **5 fichiers conservés**. Après installation de WordPress, la dernière sauvegarde contient **12 tables (32 747 octets)**.

## Réponses aux questions

**Pourquoi Vault ?** Un mot de passe poussé en clair sur GitHub est public **et reste dans l'historique Git** même après suppression. Avec Vault, le fichier chiffré peut être versionné ; seul le **mot de passe Vault** reste secret (fichier `.vault_pass` ignoré par Git, ou credential « Secret file » dans Jenkins).

**Dans quelles tâches ajouter `no_log: true` si le mot de passe apparaissait dans les logs ?** Dans toutes celles qui **manipulent un secret dans leurs paramètres ou leur résultat** : la génération du `docker-compose.yml` (en mode `--diff`, le contenu serait affiché), le démarrage de la stack, et toute tâche `command`/`shell`/`docker_container_exec` dont la ligne de commande contient le mot de passe (cas du `mariadb-dump` du défi, et du dump lui-même dont le contenu est sensible). Attention : `no_log` masque aussi les **erreurs** de la tâche (vu au TP 5.4).
