# TP 3.1 – Installation de Jenkins en conteneur

**Objectif :** installer Jenkins avec Docker Compose de façon reproductible : données persistées, accès à Docker sans `chmod 666`, outils (Docker, kubectl, Ansible) et plugins préinstallés.

**Statut :** ✅ réalisé et vérifié – preuves dans [`preuves/`](preuves/)

## 🧠 À mémoriser

| Commande | À quoi elle sert |
|---|---|
| `docker compose up -d --build` | construit l'image Jenkins et démarre les conteneurs en arrière-plan |
| `docker compose logs -f jenkins` | suit les journaux de Jenkins (attendre « fully up and running ») |
| `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword` | mot de passe initial pour débloquer Jenkins |
| `stat -c %g /var/run/docker.sock` | GID du groupe propriétaire du socket Docker (à mettre dans `.env`) |
| `docker exec jenkins id` | vérifie que l'utilisateur jenkins est bien dans le groupe Docker |
| `docker compose down && docker compose up -d` | recrée le conteneur : la configuration survit grâce au volume |
| `docker volume ls` | liste les volumes (dont `jenkins_home` qui contient tout Jenkins) |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`Dockerfile`](Dockerfile) | Image `jenkins/jenkins:lts-jdk21` + Docker CLI + compose + kubectl + Ansible |
| [`plugins.txt`](plugins.txt) | Plugins installés automatiquement à la construction de l'image |
| [`docker-compose.yml`](docker-compose.yml) | Jenkins + Ansible sur le réseau `minikube` (TP 2.8), socket Docker, volume `jenkins_home`, IP fixes |
| [`env.exemple`](env.exemple) | Contenu du fichier `.env` (GID du socket Docker) |
| [`verif-outils.Jenkinsfile`](verif-outils.Jenkinsfile) | Pipeline de vérification des outils |

> Adaptation : Jenkins et Ansible ont des **IP fixes** (`.10`, `.11`) sur le réseau `minikube`, sinon au redémarrage de la VM Jenkins prenait l'IP `.2` de Minikube et Minikube ne démarrait plus (`Address already in use`).

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `echo "DOCKER_GID=$(stat -c %g /var/run/docker.sock)" > .env` | Récupère le groupe propriétaire du socket Docker et l'écrit dans `.env` |
| `docker compose up -d --build` | Construit l'image Jenkins puis démarre les conteneurs en arrière-plan |
| `docker compose logs -f jenkins` | Suit le démarrage (attendre `Jenkins is fully up and running`) |
| `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword` | Mot de passe initial pour débloquer Jenkins |
| `docker exec jenkins id` | Vérifie que l'utilisateur `jenkins` est dans le groupe du socket (984) |
| `docker compose down` puis `docker compose up -d` | Supprime et recrée le conteneur : preuve de persistance |
| `docker volume ls \| grep jenkins_home` | Le volume qui contient **toute** la configuration Jenkins |
| `docker run --rm -v devops-tp_jenkins_home:/source:ro -v "$PWD":/backup alpine tar czf /backup/jenkins_home_$(date +%F).tar.gz -C /source .` | Sauvegarde le volume dans une archive `.tar.gz` |

Dans le job `verif-outils` (pipeline) :

| Commande | Rôle |
|---|---|
| `docker version` | Jenkins joint bien le démon Docker de l'hôte (via le socket) |
| `docker compose version` | Le plugin compose est disponible |
| `kubectl version --client` | kubectl est installé |
| `ansible --version` | Ansible est installé |
| `id` | Affiche les groupes : le GID du socket doit apparaître |

## Résultats obtenus
- `verif-outils` #1 : **SUCCESS** – Docker 29.9.3, Compose v5.7.0, kubectl v1.37.2, ansible-core 2.17.14, `groups=1000(jenkins),984`
- Après `docker compose down && up -d` : jobs `build` et `verif-outils` toujours présents avec leur historique
- Sauvegarde : `jenkins_home_2026-11-11.tar.gz` (406 Mo)

## Réponses / à retenir
- **Pourquoi une image personnalisée ?** Installer Docker à la main dans le conteneur disparaît à chaque recréation ; tout décrire dans un `Dockerfile` versionné rend l'installation **reproductible**.
- **Pourquoi `group_add` plutôt que `chmod 666` ?** `chmod 666` ouvre Docker (donc l'équivalent de root) à **tous** les utilisateurs de la machine, et disparaît au redémarrage. `group_add` ne donne l'accès qu'à l'utilisateur `jenkins` du conteneur.
- **Où est la configuration ?** Entièrement dans le volume `jenkins_home` : supprimer le conteneur ne perd rien, supprimer le volume perd tout → on le sauvegarde avant chaque mise à jour.
- **Plugins** : mettre à jour régulièrement (le 11/11 : 118 plugins mis à jour pour corriger des dépendances cassées et deux failles de sécurité).
