# TP 5.3 – Variables, facts, boucles et conditions

**Objectif :** écrire **un seul** playbook qui s'adapte à chaque serveur : variables par groupe et par hôte, facts, boucles, conditions, résultats de commandes réutilisés, tags et gestion d'erreurs.

**Statut :** ✅ réalisé et vérifié (défi compris) – preuves dans [`preuves/`](preuves/)

## 🧠 À mémoriser

| Commande / notion | À quoi ça sert |
|---|---|
| `group_vars/<groupe>.yml` / `host_vars/<hôte>.yml` | variables d'un groupe / d'un serveur (l'hôte l'emporte sur le groupe) |
| `ansible-playbook … -e "var=valeur"` | surcharge en ligne de commande : **priorité la plus forte** |
| `loop:` + `item` | répète une tâche pour chaque élément d'une liste |
| `when:` | n'exécute la tâche que si la condition est vraie (`'web' in group_names`) |
| `register:` + `changed_when: false` | enregistre le résultat d'une tâche (sans la marquer « changée ») |
| `tags:` + `--tags` / `--skip-tags` / `--list-tags` | n'exécuter qu'une partie du playbook |
| `block / rescue / always` | gestion d'erreurs : plan B si une tâche échoue (base du rollback) |
| `ansible web1 -m debug -a "var=group_names"` | afficher une variable (ici les groupes du serveur) |

Ordre de priorité simplifié (du plus faible au plus fort) : `defaults` d'un rôle < `group_vars/all` < `group_vars/<groupe>` < `host_vars/<hôte>` < `vars:` du play < `-e`.

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`../lab/variables.yml`](../lab/variables.yml) | Playbook du TP + `tags: [utilisateurs]` (étape 5) + bloc `block/rescue/always` (étape 6) |
| [`../lab/utilisateurs.yml`](../lab/utilisateurs.yml) | Défi : comptes créés/supprimés, clés SSH, sudo pour `operations` **seulement** sur `db` |
| [`../lab/group_vars/all.yml`](../lab/group_vars/all.yml) | Défi : liste `comptes` (nom, groupe, état, clé SSH publique optionnelle) |

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `cat group_vars/web.yml host_vars/web2.yml` | variables du groupe web et de web2 |
| `ansible-inventory --host web2 \| grep -A2 page_title` | valeur finale d'une variable pour un serveur |
| `ansible-playbook variables.yml` | exécute le playbook sur les 3 serveurs |
| `ansible-playbook variables.yml -e "page_title='Maintenance ce soir'" --limit web` | surcharge temporaire, limitée aux serveurs web |
| `ansible web1 -m setup` | tous les facts d'un serveur (104 facts de premier niveau) |
| `ansible web1 -m debug -a "var=groups"` | variable magique : tous les groupes et leurs membres |
| `ansible web1 -m debug -a "var=hostvars['db1']['ansible_port']"` | lire la variable d'**un autre** serveur |
| `ansible-playbook variables.yml --list-tags` / `--tags utilisateurs` / `--skip-tags utilisateurs` | gestion des tags |
| `ansible lab -m command -a "id dev1"` | vérifie la création d'un utilisateur |
| `ansible-playbook utilisateurs.yml` | défi : gestion déclarative des comptes |
| `ssh -i <clé> -p 2223 ana@127.0.0.1 whoami` | vérifie que la clé SSH installée fonctionne |

## Résultats obtenus
- `page_title` : web1 → `Legeni – serveurs web` (group_vars), web2 → `Legeni – web2 (canari)` (host_vars).
- `variables.yml` : facts affichés ; paquets communs différents pour web et db ; groupes `developpeurs` et `operations` (loop + `map`/`unique`) ; utilisateurs dev1, dev2, ops1 sur les 3 nœuds ; nginx **ignoré sur db1** (`skipping`, `dpkg … nginx is not installed`) ; `df -h` enregistré (`register`).
- `-e "page_title='Maintenance ce soir'"` → **web1 et web2** affichent ce titre (le `-e` bat même `host_vars`) ; relancé sans `-e` → titres normaux.
- `group_names` de web1 : `lab`, `web` ; `hostvars['db1']['ansible_port']` → `2223`.
- Tags : `--tags utilisateurs` n'exécute que *Créer les groupes* et *Créer les utilisateurs*.
- `block/rescue/always` : `/bin/false` échoue → `Échec intercepté sur web1, on continue proprement` → `Fin du bloc` ; **`failed=0 rescued=1`** sur les 3 serveurs.
- **Défi** : `ana`, `ben`, `chloe` créés, `stagiaire2` supprimé (`no such user`) ; clé SSH de `ana` installée → connexion SSH réussie ; `/etc/sudoers.d/chloe` **uniquement sur db1** (`skipping` sur web1/web2) ; `ana` n'a pas sudo (`sudo-refusé`) ; 2ᵉ passage `changed=0`.

## Réponses / à retenir

| Tâche de `variables.yml` | Notion |
|---|---|
| Afficher quelques facts | facts (`ansible_facts[...]`) |
| Installer les paquets communs | liste issue de `group_vars` (différente pour web et db) |
| Créer les groupes | `loop` + filtres `map` / `unique` |
| Créer les utilisateurs | `loop` sur une liste de dictionnaires, `loop_control.label` |
| Installer nginx uniquement… | `when` avec plusieurs conditions, `group_names` |
| Mesurer l'espace disque | `register` + `changed_when: false` |
| Publier la page | template + variable surchargée par `host_vars` |

- **Un seul playbook, des comportements différents** : les différences vivent dans les **variables** (`group_vars`, `host_vars`) et les **conditions**, pas dans des copies du playbook.
- **`block/rescue`** : si une tâche du `block` échoue, Ansible exécute le `rescue` au lieu d'arrêter → c'est ce qui permettra le **rollback automatique** du TP 5.6.
