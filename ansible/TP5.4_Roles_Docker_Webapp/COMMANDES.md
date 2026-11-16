# TP 5.4 – Les rôles : installer Docker et déployer l'application fil rouge

**Objectif :** organiser le code Ansible en **rôles réutilisables** : un rôle `docker` (installation de Docker CE) et un rôle `webapp` (application + Redis), assemblés dans un playbook de 5 lignes.

**Statut :** ✅ réalisé et vérifié (défi compris) – preuves dans [`preuves/`](preuves/)
**Image déployée :** `nedstudio/legeni-webapp:1.0.0` / `2.0.0` (poussées sur Docker Hub pour ce TP)

## 🧠 À mémoriser

| Commande / notion | À quoi ça sert |
|---|---|
| `roles/<nom>/tasks/main.yml` | tâches du rôle (point d'entrée) |
| `roles/<nom>/defaults/main.yml` | valeurs **par défaut**, faciles à surcharger (group_vars, host_vars, `-e`) |
| `roles/<nom>/meta/main.yml` → `dependencies:` | rôles exécutés automatiquement **avant** (webapp → docker) |
| `roles: [webapp]` dans un playbook | applique un rôle à des serveurs |
| `ansible-playbook site.yml -e webapp_version=2.0.0 --limit web1` | met à jour une version sur un serveur (ce que fera Jenkins) |
| `ansible-galaxy role init <nom>` | crée le squelette standard d'un rôle |
| `ansible-galaxy install -r requirements.yml` | installe les rôles/collections de la communauté |
| `no_log: true` | cache une tâche dans les logs (mots de passe)… mais cache aussi ses erreurs |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`../lab/site.yml`](../lab/site.yml) | Playbook de 5 lignes : `hosts: web`, `roles: [webapp]` |
| [`../lab/roles/docker/`](../lab/roles/docker/) | Rôle `docker` (dépôt officiel selon distribution/architecture, paquets, service, groupe docker) |
| [`../lab/roles/webapp/`](../lab/roles/webapp/) | Rôle `webapp` : réseau, Redis (volume, mot de passe, `no_log`), application, vérifications `uri`/`until` + **défi** `webapp_state` (`present`/`absent`) |
| [`../lab/group_vars/all.yml`](../lab/group_vars/all.yml) | `webapp_image: nedstudio/legeni-webapp` |
| [`../lab/host_vars/web2.yml`](../lab/host_vars/web2.yml) | web2 = préprod : `preprod`, orange, version 2.0.0 |
| [`../lab/requirements.yml`](../lab/requirements.yml) | Dépendances Galaxy (`geerlingguy.docker 7.4.1`, collections) – le rôle téléchargé est exclu de Git |
| [`../lab/tests/test_webapp.yml`](../lab/tests/test_webapp.yml) | Défi : test du rôle (`assert` sur la version, l'environnement et l'absence de port publié pour Redis) |

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `ansible-galaxy role init --init-path /tmp demo && tree /tmp/demo` | squelette standard d'un rôle |
| `tree roles/` | structure de nos rôles |
| `cat site.yml` / `ansible-playbook site.yml` | déploie l'application (Docker installé automatiquement par dépendance) |
| `curl -s localhost:8101/api/info` / `:8102` | version déployée sur web1 / web2 |
| `ansible-playbook site.yml --diff` | applique les variables de `host_vars/web2.yml` |
| `ansible-playbook site.yml -e webapp_version=2.0.0 --limit web1` | mise à jour applicative en ligne de commande |
| `ansible-playbook site.yml -e webapp_version=9.9.9 --limit web1` | version inexistante : échec sans coupure |
| `ansible-galaxy install -r requirements.yml` / `ansible-galaxy role list` | rôles de la communauté |
| `ansible-playbook site.yml -e webapp_state=absent --limit web1` | défi : désinstallation propre |
| `ansible-playbook tests/test_webapp.yml` | défi : test du rôle |

## Résultats obtenus
- 1ᵉʳ essai : échec sur l'image `legeni07/…` (variable pas encore remplacée) ; la cause était **cachée** par `no_log: true` (`censored`).
- Avec `nedstudio/legeni-webapp` : Docker installé **dans** web1 et web2 (Docker-in-Docker), application déployée, `/ready` et version vérifiés par le rôle ; web1 et web2 → `"version":"1.0.0"` ; **2ᵉ passage `changed=0`** ; aucun mot de passe dans la sortie.
- `host_vars/web2.yml` → web2 `{"env":"preprod","version":"2.0.0"}`, web1 reste en 1.0.0.
- `-e webapp_version=2.0.0 --limit web1` → web1 en 2.0.0 (`changed=1`).
- `-e webapp_version=9.9.9` → échec au **téléchargement de l'image, avant** de remplacer le conteneur : la boucle de requêtes voit **45 × HTTP 200**, aucune coupure ; web1 reste en 2.0.0.
- Galaxy : `geerlingguy.docker` 7.4.1 installé ; **32 variables** et 5 familles de systèmes (Fedora, Debian, Ubuntu, Alpine, Arch) contre **2 variables** et Ubuntu/Debian pour notre rôle.
- **Défi** : `webapp_state=absent` → plus de conteneurs ni de réseau `legeni_net`, **volume `legeni_redis` conservé** ; réinstallation OK ; `tests/test_webapp.yml` → `OK : version 1.0.0, Redis non exposé` (web1), `OK : version 2.0.0, Redis non exposé` (web2).
- Plusieurs exécutions ont échoué à cause de **coupures DNS** de la connexion (`Temporary failure in name resolution`), puis réussi une fois relancées (preuve `05a`).

## Réponses aux questions

**1. Comment l'URL du dépôt s'adapte-t-elle à la distribution et à l'architecture ?** Elle est construite avec les **facts** : `ansible_facts['distribution'] | lower` (ubuntu/debian), `ansible_facts['distribution_release']` (noble…) et `amd64`/`arm64` selon `ansible_facts['architecture']`. Le même rôle fonctionne sur plusieurs distributions et processeurs.

**2. Pourquoi installer `python3-docker` / `python3-requests` sur les nœuds ?** Les modules `community.docker.*` s'exécutent **sur le nœud** en Python et utilisent la bibliothèque Docker SDK (qui s'appuie sur `requests`) pour parler au démon Docker.

**3. Au 2ᵉ passage, si Docker est déjà installé ?** Toutes les tâches sont en `ok` (paquets présents, dépôt déjà ajouté, service déjà démarré) : `changed=0`, le handler de redémarrage n'est pas déclenché.

**Version inexistante (9.9.9) : le service est-il coupé ?** Non : le module télécharge d'abord l'image ; comme elle n'existe pas, il échoue **avant** de supprimer l'ancien conteneur, qui continue de servir (45 réponses 200 sur 45). Le playbook est en échec, ce qui doit arrêter le pipeline.

**Notre rôle ou celui de la communauté ?** `geerlingguy.docker` est plus complet (32 réglages, nombreuses distributions, maintenu et testé par la communauté) ; notre rôle est minimal mais lisible et suffisant pour le lab. En entreprise on réutilise souvent les rôles reconnus, avec une **version figée** dans `requirements.yml`.
