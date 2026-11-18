# Fiche mémo DevOps – les bases à connaître

Synthèse des TP Jenkins, Kubernetes, Ansible et du Projet CI/CD : **à quoi ça sert** et **comment l'utiliser**.

**Sommaire :** 1. La chaîne DevOps · 2. Git · 3. Docker · 4. Kubernetes (commandes, Pods, YAML) · 5. Ansible · 6. Jenkins · 7. Réflexes de dépannage

---

## 1. La chaîne DevOps en une image

```
 code ──git push──▶ GitHub ──▶ Jenkins ──▶ tests ─▶ image Docker ─▶ Docker Hub
                                   │
                                   └──▶ Ansible ──▶ Kubernetes (staging ─▶ validation ─▶ prod)
```

| Outil | Rôle en une phrase |
|---|---|
| **Git / GitHub** | historique du code ; travail en branches, intégration par pull request |
| **Docker** | emballe l'application et ses dépendances dans une **image** qui tourne partout pareil |
| **Jenkins** | **automate** : à chaque push il teste, construit, publie, déploie |
| **Kubernetes** | fait tourner les conteneurs en production : réplicas, redémarrage, mise à jour sans coupure |
| **Ansible** | **décrit** l'état voulu des serveurs (installation, configuration, déploiement) dans des fichiers YAML rejouables |

Mots clés : **CI** (intégration continue : tester chaque modification), **CD** (livraison/déploiement continu), **IaC** (Infrastructure as Code : l'infrastructure décrite dans des fichiers versionnés), **idempotence** (relancer = même résultat, rien ne change si tout est déjà bon).

---

## 2. Git

| Commande | À quoi ça sert |
|---|---|
| `git clone <url>` | copie un dépôt distant sur la machine |
| `git status` | ce qui est modifié / nouveau / prêt à commiter |
| `git add <fichier>` | prépare un fichier pour le prochain commit |
| `git commit -m "message clair"` | enregistre une version dans l'historique |
| `git push -u origin <branche>` | envoie la branche sur GitHub (`-u` : mémorise le lien) |
| `git pull` | récupère et applique les nouveautés du dépôt distant |
| `git checkout -b feature/x` | crée une branche et bascule dessus |
| `git checkout main` | change de branche |
| `git log --oneline -5` | les 5 derniers commits, une ligne chacun |
| `git diff` | les lignes modifiées et pas encore commitées |
| `git branch -d <branche>` | supprime une branche locale **déjà fusionnée** |
| `git fetch --prune` | met à jour la liste des branches distantes, oublie les supprimées |
| `git tag -a v1.0.0 -m "..."` + `git push origin v1.0.0` | marque une version (mise en production) |

**Flux de travail à retenir :** `branche feature/…` → commit → push → **pull request** → build Jenkins vert → **merge** → `git pull` sur `main` → supprimer la branche.

---

## 3. Docker

### Commandes
| Commande | À quoi ça sert |
|---|---|
| `docker build -t nom:1.0.0 .` | construit une image à partir du `Dockerfile` du dossier courant |
| `docker build --target test .` | ne construit qu'une étape d'un Dockerfile multi-stage (ex. les tests) |
| `docker build --build-arg APP_VERSION=1.0.0 …` | passe une valeur au Dockerfile (`ARG`) |
| `docker images` | images présentes sur la machine |
| `docker run -d --name web -p 8080:5000 nom:1.0.0` | lance un conteneur en arrière-plan (`-d`), port machine 8080 → conteneur 5000 |
| `docker run --rm -it image sh` | conteneur jetable (`--rm`) avec un terminal interactif (`-it`) |
| `docker ps` / `docker ps -a` | conteneurs en cours / tous, y compris arrêtés |
| `docker logs -f web` | journaux du conteneur (`-f` : en continu) |
| `docker exec -it web sh` | ouvre un terminal **dans** un conteneur qui tourne |
| `docker stop web` / `docker rm web` | arrête / supprime un conteneur |
| `docker inspect web` | toute la configuration (IP, volumes, variables…) |
| `docker login -u user --password-stdin` | se connecter au registre (mot de passe lu sur l'entrée standard) |
| `docker push nedstudio/app:1.0.0` | publie l'image sur Docker Hub |
| `docker compose up -d` / `down` / `ps` / `logs` | démarre / arrête / liste / journaux de **plusieurs** conteneurs décrits dans `docker-compose.yml` |

### Le Dockerfile, ligne par ligne
```dockerfile
FROM python:3.12-slim AS base          # image de départ (slim = légère) ; « AS base » nomme l'étape
WORKDIR /app                           # dossier de travail dans l'image (créé si besoin)
COPY requirements.txt .                # copie d'abord les dépendances seules => couche gardée en cache
RUN pip install --no-cache-dir -r requirements.txt   # commande exécutée PENDANT le build

FROM base AS test                      # 2e étape : réutilise « base »
COPY . .
RUN flake8 . && pytest -q              # si un test échoue, le build échoue => pas d'image

FROM base AS runtime                   # étape finale, sans les outils de test (multi-stage)
ARG APP_VERSION=dev                    # valeur fournie au build (--build-arg)
ENV APP_VERSION=${APP_VERSION}         # variable d'environnement disponible à l'exécution
RUN useradd --uid 10001 appuser        # utilisateur sans droits root (sécurité)
COPY app.py .
USER appuser                           # le conteneur ne tourne PAS en root
EXPOSE 5000                            # documente le port écouté
HEALTHCHECK CMD python -c "..." || exit 1   # Docker vérifie régulièrement que l'appli répond
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]   # forme exec (liste) : reçoit bien SIGTERM => arrêt propre
```

### docker-compose.yml
```yaml
services:
  web:                                  # nom du service (= nom DNS sur le réseau du projet)
    image: nedstudio/legeni-webapp:1.0.0
    ports: ["8080:5000"]                # machine:conteneur
    environment:                        # configuration par variables d'environnement
      REDIS_HOST: redis
    depends_on: [redis]                 # démarre redis avant web
  redis:
    image: redis:7.4-alpine
    volumes: [redis_data:/data]         # données conservées hors du conteneur
volumes:
  redis_data:
```

---

## 4. Kubernetes

### Vocabulaire
| Objet | Rôle |
|---|---|
| **Pod** | plus petite unité : un (ou plusieurs) conteneur(s) avec une IP ; **éphémère** |
| **Deployment** | maintient N Pods identiques, gère les **mises à jour** (rolling update) et les **rollbacks** |
| **ReplicaSet** | créé par le Deployment, garantit le nombre de Pods (on ne le manipule pas directement) |
| **Service** | adresse **stable** + répartition de charge vers des Pods (choisis par **labels**) |
| **Ingress** | entrée HTTP(S) par nom de domaine (`legeni.local`) vers les Services |
| **ConfigMap / Secret** | configuration / données sensibles injectées dans les Pods |
| **Namespace** | « dossier » qui isole des environnements (`legeni-staging`, `legeni-prod`) |
| **StatefulSet + PVC** | applications avec données (bases, Redis) : nom stable + disque persistant |
| **Job / CronJob / DaemonSet** | tâche ponctuelle / planifiée / un Pod sur chaque nœud |

### Commandes kubectl essentielles
| Commande | À quoi ça sert |
|---|---|
| `kubectl get nodes` | nœuds du cluster et leur état |
| `kubectl get pods` (`-o wide`, `-A`, `-n <ns>`, `-w`) | liste les Pods (`-o wide` : IP et nœud ; `-A` : tous les namespaces ; `-w` : suivre en direct) |
| `kubectl get all -n <ns>` | Pods, Services, Deployments, ReplicaSets d'un namespace |
| `kubectl apply -f fichier.yaml` | crée **ou met à jour** les objets décrits (méthode déclarative, à privilégier) |
| `kubectl delete -f fichier.yaml` / `kubectl delete pod <nom>` | supprime |
| `kubectl describe pod <nom>` | détail + **Events** (en bas) : **le premier réflexe en cas de problème** |
| `kubectl logs <pod>` (`-f`, `--previous`, `-c <conteneur>`) | journaux ; `--previous` = ceux du conteneur qui a planté |
| `kubectl exec -it <pod> -- sh` | terminal dans un Pod |
| `kubectl port-forward pod/<nom> 8080:5000` | accès local temporaire à un Pod ou Service |
| `kubectl run test --image=nginx --rm -it -- sh` | Pod jetable pour tester |
| `kubectl get pod <nom> -o yaml` | la configuration complète, telle que stockée dans le cluster |
| `kubectl explain pod.spec.containers` | documentation d'un champ YAML |
| `kubectl create namespace dev` / `kubectl config set-context --current --namespace=dev` | crée un namespace / le choisit par défaut |
| `kubectl scale deployment webapp --replicas=5` | change le nombre de Pods |
| `kubectl set image deployment/webapp webapp=image:2.0.0` | change l'image => rolling update |
| `kubectl rollout status deployment/webapp` | suit la mise à jour jusqu'à la fin |
| `kubectl rollout history deployment/webapp` | révisions précédentes |
| `kubectl rollout undo deployment/webapp` | **rollback** à la révision précédente |
| `kubectl rollout restart deployment/webapp` | recrée les Pods (ex. après modification d'une ConfigMap) |
| `kubectl top pods` | consommation CPU / mémoire (addon metrics-server) |
| `kubectl get events --sort-by=.lastTimestamp` | derniers événements du namespace |
| `kubectl apply -k overlays/prod` | applique une configuration **Kustomize** |
| `minikube start` / `status` / `ip` / `service <svc> --url` / `addons enable ingress` | gérer le cluster local |
| `helm install <nom> <chart>` / `helm list` / `helm uninstall <nom>` | installer des applications empaquetées (charts) |

### États d'un Pod et que faire
| État | Signification | Réflexe |
|---|---|---|
| `Pending` | pas encore placé sur un nœud | `describe` : ressources insuffisantes ? PVC non `Bound` ? |
| `ContainerCreating` | image en téléchargement / volumes en montage | patienter, sinon `describe` |
| `Running` `1/1` | OK et **prêt** (readinessProbe réussie) | — |
| `Running` `0/1` | tourne mais **pas prêt** : ne reçoit pas de trafic | readinessProbe : mauvais chemin, dépendance absente |
| `ImagePullBackOff` / `ErrImagePull` | image introuvable | nom / tag faux, dépôt privé, pas d'accès réseau |
| `CrashLoopBackOff` | le conteneur démarre puis plante en boucle | `kubectl logs --previous` |
| `OOMKilled` | dépassement de la limite mémoire | augmenter `limits.memory` ou corriger la fuite |
| `CreateContainerConfigError` | ConfigMap ou Secret référencé inexistant | `describe`, vérifier les noms |
| `Terminating` | en cours de suppression | normal pendant un rolling update |

### Pod (YAML commenté)
```yaml
apiVersion: v1                 # version de l'API Kubernetes pour ce type d'objet
kind: Pod                      # type d'objet
metadata:
  name: webapp                 # nom unique dans le namespace
  labels:                      # étiquettes : servent aux Services et Deployments pour « trouver » le Pod
    app: webapp
spec:                          # l'état souhaité
  containers:
    - name: webapp
      image: nedstudio/legeni-webapp:1.0.0   # toujours un tag précis, jamais « latest » en prod
      ports:
        - containerPort: 5000  # port écouté par l'application
      env:                     # variables d'environnement
        - name: APP_ENV
          value: dev
```

### Deployment + Service (YAML commenté)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: legeni-prod
spec:
  replicas: 3                          # nombre de Pods voulus
  revisionHistoryLimit: 5              # révisions gardées pour les rollbacks
  strategy:
    type: RollingUpdate                # remplace les Pods progressivement
    rollingUpdate:
      maxSurge: 1                      # au plus 1 Pod en plus pendant la mise à jour
      maxUnavailable: 0                # jamais moins de 3 Pods prêts => pas de coupure
  selector:
    matchLabels: {app: webapp}         # le Deployment gère les Pods qui ont ce label…
  template:                            # …et voici le modèle de ces Pods
    metadata:
      labels: {app: webapp}            # doit correspondre au selector
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: webapp
          image: nedstudio/legeni-webapp:1.1.0-14
          ports: [{containerPort: 5000}]
          envFrom:                     # toutes les clés deviennent des variables d'environnement
            - configMapRef: {name: webapp-config}
            - secretRef: {name: redis-secret}
          readinessProbe:              # « prêt à recevoir du trafic ? » sinon retiré du Service
            httpGet: {path: /ready, port: 5000}
            periodSeconds: 5
          livenessProbe:               # « encore vivant ? » sinon le conteneur est redémarré
            httpGet: {path: /health, port: 5000}
            initialDelaySeconds: 5
          resources:
            requests: {cpu: 50m, memory: 64Mi}    # réservé : sert au placement sur un nœud
            limits:   {cpu: 200m, memory: 128Mi}  # plafond : CPU freiné, mémoire dépassée => OOMKilled
          lifecycle:
            preStop:                   # avant l'arrêt : 5 s pour que le Service retire le Pod => 0 erreur
              exec: {command: ["sleep", "5"]}
---                                    # sépare plusieurs objets dans un même fichier
apiVersion: v1
kind: Service
metadata:
  name: webapp                         # nom DNS dans le cluster : http://webapp
spec:
  type: NodePort                       # ClusterIP (interne, par défaut) | NodePort (port sur le nœud) | LoadBalancer
  selector: {app: webapp}              # envoie le trafic aux Pods portant ce label
  ports:
    - port: 80                         # port du Service
      targetPort: 5000                 # port du conteneur
      nodePort: 30082                  # port ouvert sur le nœud (30000-32767)
```

### ConfigMap, Secret, Ingress, StatefulSet (l'essentiel)
```yaml
apiVersion: v1
kind: ConfigMap                 # configuration NON sensible
metadata: {name: webapp-config}
data:
  APP_COLOR: "#2da44e"
---
apiVersion: v1
kind: Secret                    # données sensibles (encodées en base64, pas chiffrées !)
metadata: {name: redis-secret}
type: Opaque
stringData:                     # stringData : on écrit en clair, Kubernetes encode
  REDIS_PASSWORD: "..."         # => jamais commité en clair : Vault, credential Jenkins, etc.
---
apiVersion: networking.k8s.io/v1
kind: Ingress                   # routage HTTP par nom de domaine
metadata: {name: webapp}
spec:
  ingressClassName: nginx
  tls: [{hosts: [legeni.local], secretName: legeni-tls}]   # HTTPS
  rules:
    - host: legeni.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: webapp, port: {number: 80}}}
---
apiVersion: apps/v1
kind: StatefulSet               # Pods avec identité stable (redis-0) + disque propre
metadata: {name: redis}
spec:
  serviceName: redis
  replicas: 1
  selector: {matchLabels: {app: redis}}
  template: { ... }             # comme un Deployment
  volumeClaimTemplates:         # crée un PVC (disque persistant) par Pod
    - metadata: {name: data}
      spec:
        accessModes: [ReadWriteOnce]
        resources: {requests: {storage: 1Gi}}
```

---

## 5. Ansible

### Commandes
| Commande | À quoi ça sert |
|---|---|
| `ansible all -m ping` | teste la connexion à tous les serveurs de l'inventaire |
| `ansible web -m command -a "uptime"` | commande **ad-hoc** sur un groupe |
| `ansible web -b -m apt -a "name=nginx state=present"` | module ad-hoc avec droits root (`-b` = become) |
| `ansible web1 -m setup` | les **facts** d'un serveur (OS, mémoire, IP…) |
| `ansible-inventory --graph` | arbre des groupes et des hôtes |
| `ansible-playbook site.yml` | exécute un playbook |
| `--syntax-check` / `--check --diff` / `--list-tasks` | vérifier la syntaxe / simuler en montrant les différences / lister les tâches |
| `--limit web1` / `--tags x` / `-e "var=val"` | restreindre aux serveurs / aux tâches taguées / forcer une variable (priorité max) |
| `-K` | demande le mot de passe sudo |
| `ansible-vault encrypt / view / edit fichier.yml` | chiffrer / lire / modifier un fichier de secrets |
| `--vault-password-file ~/.secrets/vault_pass` (ou `--ask-vault-pass`) | fournir le mot de passe Vault au playbook |
| `ansible-galaxy role init <nom>` / `ansible-galaxy install -r requirements.yml` | créer un rôle / installer des rôles et collections |

Lire le **PLAY RECAP** : `ok` (déjà bon), `changed` (modifié), `failed` (erreur), `skipped` (condition fausse), `rescued` (erreur rattrapée). 2ᵉ exécution `changed=0` = **idempotent**.

### Inventaire
```ini
[web]                                   # groupe
web1 ansible_host=127.0.0.1 ansible_port=2221
web2 ansible_host=127.0.0.1 ansible_port=2222

[db]
db1 ansible_host=127.0.0.1 ansible_port=2223

[lab:children]                          # groupe de groupes
web
db

[all:vars]                              # variables pour tous
ansible_user=ansible
```

### Playbook commenté
```yaml
---
- name: Installer et configurer nginx  # un « play » : quels serveurs, quelles tâches
  hosts: web                            # groupe de l'inventaire
  become: true                          # exécuter en root (sudo)
  vars:
    page_title: "Legeni"                # variable (surchargée par group_vars, host_vars, -e)
  tasks:
    - name: Installer nginx             # chaque tâche = un module + ses paramètres
      ansible.builtin.apt:
        name: nginx
        state: present                  # état voulu (present/absent/latest) => idempotent
        update_cache: true

    - name: Publier la page
      ansible.builtin.template:         # fichier généré depuis un modèle Jinja2 ({{ variable }})
        src: templates/index.html.j2
        dest: /var/www/html/index.html
      notify: Recharger nginx           # déclenche le handler SEULEMENT si la tâche a changé quelque chose

    - name: Créer les utilisateurs
      ansible.builtin.user:
        name: "{{ item }}"
      loop: [dev1, dev2]                # répète la tâche pour chaque élément
      when: "'web' in group_names"      # condition

    - name: Mesurer le disque
      ansible.builtin.command: df -h
      register: disque                  # garde le résultat dans une variable
      changed_when: false               # une lecture ne « change » rien

    - name: Déployer avec plan B
      block:                            # si une tâche du block échoue…
        - ansible.builtin.command: /bin/false
      rescue:                           # …on exécute ceci (ex. rollback)
        - ansible.builtin.debug: {msg: "échec intercepté"}
      always:                           # exécuté dans tous les cas
        - ansible.builtin.debug: {msg: "fin"}

  handlers:
    - name: Recharger nginx             # exécuté une seule fois, à la fin du play
      ansible.builtin.service:
        name: nginx
        state: reloaded
```

### Organisation d'un projet Ansible
```
ansible/
├── ansible.cfg            # réglages (inventaire par défaut, dossier des rôles…)
├── inventory.ini          # les serveurs
├── group_vars/web.yml     # variables d'un groupe
├── host_vars/web2.yml     # variables d'un serveur (priorité > groupe)
├── vars/vault.yml         # secrets chiffrés (ansible-vault)
├── site.yml               # playbook : « hosts: web » + « roles: [webapp] »
└── roles/webapp/
    ├── tasks/main.yml     # les tâches du rôle
    ├── defaults/main.yml  # valeurs par défaut (priorité la plus faible)
    ├── handlers/main.yml
    ├── templates/         # fichiers .j2
    └── meta/main.yml      # dépendances (ex. le rôle docker avant)
```
Priorité des variables (faible → forte) : `defaults` du rôle < `group_vars` < `host_vars` < `vars:` du play < `-e`.

---

## 6. Jenkins

### Notions
| Notion | À quoi ça sert |
|---|---|
| **Job freestyle** | job configuré par l'interface (TP 3.2–3.4) |
| **Pipeline** | job décrit par un `Jenkinsfile` versionné avec le code (TP 3.5+) |
| **Multibranch** | un job par branche et par pull request, détectés automatiquement |
| **Webhook** | GitHub prévient Jenkins à chaque push (au lieu de vérifier périodiquement) |
| **Credentials** | secrets stockés dans Jenkins (Docker Hub, kubeconfig, Vault…), jamais dans le code |
| **Agent** | là où s'exécutent les étapes (`agent any`, ou un conteneur Docker) |
| **Artefact / rapports** | fichiers gardés (`archiveArtifacts`), résultats de tests (`junit`), couverture, avertissements |
| **Stage View** | vue graphique des étapes de chaque build |
| **Build vert / rouge / gris** | succès / échec / annulé |

### Jenkinsfile déclaratif commenté
```groovy
pipeline {
    agent any                                   // n'importe quel exécuteur disponible
    environment {                               // variables pour tout le pipeline
        IMAGE = 'nedstudio/legeni-webapp'
    }
    options {
        timestamps()                            // heure sur chaque ligne de log
        timeout(time: 60, unit: 'MINUTES')      // abandon si trop long
        disableConcurrentBuilds()               // jamais 2 builds du même job en même temps
    }
    stages {
        stage('Qualité') {
            parallel {                          // les sous-stages tournent EN MÊME TEMPS
                stage('Tests') {
                    agent { docker { image 'python:3.12-slim'; reuseNode true } }   // étape dans un conteneur
                    steps { sh 'pytest --junitxml=reports/junit.xml' }
                    post { always { junit 'reports/junit.xml' } }   // publie le rapport même en cas d'échec
                }
                stage('Lint') { steps { sh 'flake8 .' } }
            }
        }
        stage('Build') {
            steps { sh 'docker build -t $IMAGE:$BUILD_NUMBER .' }   // BUILD_NUMBER : fourni par Jenkins
        }
        stage('Push') {
            when { branch 'main' }              // seulement sur main
            steps {
                withCredentials([usernamePassword(credentialsId: 'registry-credentials',
                                 usernameVariable: 'U', passwordVariable: 'P')]) {  // secret injecté et masqué dans les logs
                    sh 'echo "$P" | docker login -u "$U" --password-stdin && docker push $IMAGE:$BUILD_NUMBER'
                }
            }
        }
        stage('Validation') {
            when { branch 'main' }
            steps { input message: 'Déployer en production ?', ok: 'Déployer' }   // pause jusqu'au clic humain
        }
        stage('Production') {
            when { branch 'main' }
            steps { sh 'ansible-playbook deploy.yml -e target_env=prod' }
        }
    }
    post {                                      // après tous les stages
        success { echo 'OK' }
        failure { emailext to: 'moi@exemple.com', subject: "Échec ${env.JOB_NAME}", body: "${env.BUILD_URL}" }
        cleanup { cleanWs() }                   // nettoie l'espace de travail
    }
}
```
Variables utiles : `BUILD_NUMBER`, `JOB_NAME`, `BRANCH_NAME`, `BUILD_URL`, `WORKSPACE`.

---

## 7. Réflexes de dépannage

| Symptôme | Commandes |
|---|---|
| Un Pod ne démarre pas | `kubectl get pods` → `kubectl describe pod <nom>` (Events) → `kubectl logs <nom> --previous` |
| Le Service ne répond pas | `kubectl get endpoints <svc>` (vide = selector/labels faux ou Pods pas prêts) ; `kubectl port-forward` pour tester |
| Conteneur Docker qui s'arrête | `docker ps -a` → `docker logs <nom>` → `docker inspect <nom>` |
| Playbook en échec | relire le message `fatal`, relancer avec `-v` (ou `-vvv`), tester avec `--check --diff` ; attention : `no_log: true` cache aussi les erreurs |
| Build Jenkins rouge | *Console Output* du build : le premier `ERROR` / `FAILED` ; vérifier les credentials et le stage concerné |
| Mise à jour qui coupe le service | `maxUnavailable: 0`, readinessProbe correcte, plusieurs réplicas, `preStop` |
| Retour arrière urgent | `kubectl rollout undo deployment/<nom>` (ou rollback automatique du playbook) |

**Règles d'or :** un tag d'image précis (jamais `latest` en prod) · aucun secret en clair dans Git · tout dans des fichiers versionnés (Dockerfile, YAML, Jenkinsfile, playbooks) · tester avant de déployer · toujours savoir revenir en arrière.
