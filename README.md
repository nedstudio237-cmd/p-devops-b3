# TP DevOps B3 – EVINA ZE ROMARIC

Réalisation des TPs du dépôt [Legeni07/tp_devops_b3](https://github.com/Legeni07/tp_devops_b3) : **Jenkins**, **Kubernetes** et **Ansible**.

Chaque dossier de TP contient :
- les **fichiers réalisés** (manifestes, scripts, Jenkinsfile, playbooks…) ;
- **`COMMANDES.md`** : les commandes utilisées et leur rôle, plus les réponses aux questions ;
- **`preuves/`** : les sorties des commandes qui prouvent que le TP fonctionne.

## Environnement

Ubuntu 24.04 (VM VMware), Docker 29, Minikube (driver Docker), Jenkins et Ansible en Docker Compose sur le réseau `minikube` (TP 2.8).

## Avancement

### Jenkins
| TP | Sujet | Statut |
|---|---|---|
| 3.1 | [Installation](jenkins/TP3.1_Installation/) | ✅ |
| 3.2 | [Job freestyle `build`](jenkins/TP3.2_Build/) | ✅ |
| 3.3 | [Test d'acceptance](jenkins/TP3.3_Test_acceptance/) | ✅ |
| 3.4 | [Artefact Docker Hub](jenkins/TP3.4_Artefact/) | ✅ |
| 3.5 | [Jenkinsfile](jenkins/TP3.5_Jenkinsfile/) | ✅ |
| 3.6 | [Multibranch + webhook](jenkins/TP3.6_Multibranch_Webhook/) | ✅ (webhook non fait) |
| 3.7 | [Qualité, tests parallèles](jenkins/TP3.7_Qualite_Tests_Paralleles/) | ✅ |
| 3.8 | Déploiement continu | ⏸ en attente (fusion sur main + Gmail) |

### Kubernetes
| TP | Sujet | Statut |
|---|---|---|
| 4.1 | [Installation du cluster](kubernetes/TP4.1_Installation_cluster/) | ✅ |
| 4.2 | [Le Pod](kubernetes/TP4.2_Pod/) | ✅ |
| 4.3 | Deployment et Service | ⏳ |
| 4.4 | Webapp fil rouge | ⏳ |
| 4.5 | WordPress + MySQL | ⏳ |
| 4.6 | Jobs, CronJobs, DaemonSet | ⏳ |
| 4.7 | Namespace, ConfigMap, Secret | ⏳ |
| 4.8 | Scaling, rolling update, rollback | ⏳ |
| 4.9 | Probes et ressources | ⏳ |
| 4.10 | Stockage, StatefulSet | ⏳ |
| 4.11 | Ingress | ⏳ |
| 4.12 | Kustomize | ⏳ |
| 4.13 | Dépannage | ⏳ |

### Ansible
| TP | Sujet | Statut |
|---|---|---|
| 5.1 | Lab, inventaire, ad-hoc | ⏳ |
| 5.2 | Premier playbook | ⏳ |
| 5.3 | Variables, conditions, boucles | ⏳ |
| 5.4 | Rôles Docker + webapp | ⏳ |
| 5.5 | Vault + WordPress | ⏳ |
| 5.6 | Ansible + Kubernetes | ⏳ |
