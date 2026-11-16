# TP 5.1 – Mise en place du lab, inventaire et commandes ad-hoc

**Objectif :** disposer d'une machine de contrôle Ansible et de **3 serveurs cibles**, écrire un inventaire, et administrer les serveurs à distance **sans agent** (uniquement SSH + Python).

**Statut :** ✅ réalisé et vérifié (défi compris) – preuves dans [`preuves/`](preuves/)

```
 Machine de contrôle (VM Ubuntu)              Nœuds gérés (conteneurs Ubuntu 24.04 + systemd + SSH)
 ansible, ansible-playbook   ── SSH :2221 ──▶  web1   (ports web 8001 / 8101)
 inventory.ini / ansible.cfg ── SSH :2222 ──▶  web2   (ports web 8002 / 8102)
 keys/id_ansible             ── SSH :2223 ──▶  db1    (ports web 8003 / 8103)
```

## 🧠 À mémoriser

| Commande | À quoi elle sert |
|---|---|
| `ansible all -m ping` | vérifie la connexion SSH + Python sur tous les serveurs (`pong`) |
| `ansible <cible> -m <module> -a "<arguments>"` | commande **ad-hoc** : une action sur des serveurs, sans playbook |
| `-b` (become) | exécute avec `sudo` (installer, créer un utilisateur…) |
| `ansible-inventory --graph` | arborescence des groupes et des serveurs |
| `ansible-inventory --host web1` | variables d'un serveur |
| `ansible all -m setup -a "filter=ansible_kernel"` | **facts** : informations collectées sur les serveurs |
| `ansible 'web:!web2'` / `'lab:&web'` / `--limit db1` | ciblage : exclusion, intersection, limitation |
| `CHANGED` (jaune) / `SUCCESS` (vert) | modifié / déjà dans l'état voulu (idempotence) |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`../lab/`](../lab/) | Lab du cours copié dans le dépôt (Dockerfile des nœuds, `docker-compose.yml`, `ansible.cfg`, `inventory.ini`…) ; la paire de clés `keys/id_ansible` est générée localement et exclue de Git |
| [`../lab/inventory.yml`](../lab/inventory.yml) | Le même inventaire au format **YAML** |

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `sudo apt install -y ansible` | installe Ansible sur la machine de contrôle |
| `ansible --version` | version et fichier de configuration utilisé |
| `ansible-galaxy collection list \| grep -E 'community.docker\|kubernetes.core'` | collections nécessaires aux TPs suivants |
| `ssh-keygen -t ed25519 -f keys/id_ansible -N ""` | paire de clés SSH dédiée au lab (sans phrase de passe) |
| `docker compose up -d --build` | construit et démarre les 3 nœuds |
| `ssh -i keys/id_ansible -p 2221 ansible@127.0.0.1 hostname` | test SSH manuel |
| `cat ansible.cfg inventory.ini` | configuration et inventaire du lab |
| `ansible-inventory -i inventory.yml --graph` | vérifie l'inventaire YAML |
| `ansible web -m command -a "uptime"` | commande simple sur un groupe |
| `ansible db1 -m shell -a "df -h / \| tail -1"` | commande avec tube (`shell` nécessaire) |
| `ansible web -b -m apt -a "name=tree state=present update_cache=yes"` | installe un paquet |
| `ansible all -b -m user -a "name=stagiaire shell=/bin/bash"` | crée un utilisateur |
| `ansible all -b -m copy -a "content='…' dest=/etc/motd mode=0644"` | écrit un fichier |
| `ansible all -b -m user -a "name=stagiaire state=absent remove=yes"` | supprime un utilisateur et son dossier |
| `ansible all -m lineinfile -a "path=… line=\"…\""` | garantit qu'une ligne est présente dans un fichier |
| `ansible all -m ping -f 1 -v` | 1 serveur à la fois (`-f` = forks), mode verbeux |
| `docker compose stop` / `docker compose down -v` | arrête le lab / repart de serveurs vierges |

## Résultats obtenus
- Ansible **core 2.16.3**, collections `community.docker 3.7.0` et `kubernetes.core 2.4.0` présentes.
- Lab : `lab-web1-1`, `lab-web2-1`, `lab-db1-1` démarrés ; SSH manuel OK.
- `ansible-inventory --graph` : groupes `lab` (→ `web` : web1, web2 ; `db` : db1) et `wordpress_servers` (db1). `inventory.yml` **équivalent** (seul l'ordre d'affichage des groupes diffère).
- `ansible all -m ping` → **3 `pong`** ; Ubuntu 24.04 ; facts mémoire et disque récupérés.
- `tree` installé sur web ; `tree /etc/nginx` → `FAILED` (normal : nginx absent) ; utilisateur `stagiaire` et `/etc/motd` créés sur les 3 nœuds.
- **Idempotence** : 1ʳᵉ fois `CHANGED`, 2ᵉ fois `SUCCESS` (apt, user) ; avec `shell "echo ligne >> …"` → `CHANGED` à chaque fois et le fichier grossit (2 lignes après 2 exécutions).
- Ciblage : `'web:!web2'` → web1 ; `'lab:&web'` → web1, web2 ; `--limit db1` → db1.
- **Défi** : noyau `7.0.0-42-generic` (les nœuds sont des conteneurs : ils partagent le noyau de la VM) ; `stagiaire` supprimé ; `lineinfile` → `SUCCESS` dès la 1ʳᵉ fois car le `.bashrc` d'Ubuntu contient **déjà** `alias ll='ls -alF'` (ligne 91) : rien à ajouter.

## Réponses aux questions

**1. Les groupes ? Que contient `lab` ?** Groupes `web` (web1, web2), `db` (db1), `wordpress_servers` (db1) et `lab`, groupe **parent** (`[lab:children]`) qui contient `web` et `db`, donc les 3 serveurs.

**2. Où sont définies la clé SSH et l'utilisateur ?** Dans `[lab:vars]` de `inventory.ini` : `ansible_user=ansible` et `ansible_ssh_private_key_file=keys/id_ansible` (valables pour tous les serveurs du groupe `lab`).

**3. Pourquoi `host_key_checking = False` est acceptable en lab mais pas en production ?** En lab, les nœuds sont recréés souvent (leur clé d'hôte change) et tout est local. En production, vérifier la clé d'hôte protège contre l'**usurpation de serveur** (attaque *man-in-the-middle*) : désactiver la vérification, c'est accepter de se connecter à n'importe quelle machine qui répond à cette adresse.

**Pourquoi préférer les modules (`apt`, `user`, `copy`, `lineinfile`) à `command`/`shell` ?** Les modules sont **idempotents** : ils vérifient l'état actuel et n'agissent que si nécessaire (`SUCCESS` sinon), ils renvoient un vrai statut (changé ou non) et sont portables. `command`/`shell` exécutent la commande **à chaque fois** (toujours `CHANGED`), sans savoir si c'était utile, ce qui peut casser un système (ex. ligne ajoutée en double).
