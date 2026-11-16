# TP 5.6 – Ansible pilote Kubernetes : déploiement multi-environnement avec rollback

**Objectif :** utiliser Ansible pour **générer et appliquer** les manifestes Kubernetes de l'application en *staging* ou en *prod*, attendre la fin du rolling update, tester, et **revenir automatiquement en arrière** en cas d'échec. C'est la brique « déploiement » que Jenkins appellera dans le projet final.

**Statut :** ✅ réalisé et vérifié (étape 7 comprise) – preuves dans [`preuves/`](preuves/) – **un bug du playbook fourni a été trouvé et corrigé**

## 🧠 À mémoriser

| Commande / notion | À quoi ça sert |
|---|---|
| `kubernetes.core.k8s` (`definition:`, `template:`, `src:`) | crée / met à jour des objets Kubernetes depuis Ansible (comme `kubectl apply`) |
| `wait: true` + `wait_timeout:` | Ansible attend que les Pods de la nouvelle version soient **prêts** |
| `kubernetes.core.k8s_exec` | exécute une commande dans un Pod (smoke test) |
| `kubernetes.core.k8s_rollback` | revient à la révision précédente d'un Deployment |
| `block` / `rescue` | si le déploiement ou le test échoue → rollback automatique |
| `ansible.builtin.fail` dans le `rescue` | termine le playbook en **échec** pour que le pipeline passe au rouge |
| `ansible-playbook k8s_deploy.yml -e target_env=prod -e app_version=2.0.0` | un seul playbook, l'environnement et la version en paramètres |
| `lookup('kubernetes.core.k8s', kind='Pod', …)` | lit des objets du cluster depuis Ansible |

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`../lab/k8s_deploy.yml`](../lab/k8s_deploy.yml) | Playbook : namespace, Secret Redis (`no_log`), manifestes (template) + `wait`, smoke test, `rescue` avec rollback — **smoke test corrigé** |
| [`k8s_deploy.original-du-cours.yml`](k8s_deploy.original-du-cours.yml) | Version d'origine, pour comparaison |
| [`../lab/templates/k8s/webapp.yml.j2`](../lab/templates/k8s/webapp.yml.j2) | ConfigMap, StatefulSet + Service Redis, Deployment (probes, `maxUnavailable: 0`, annotation `checksum/config`) + Service NodePort |
| [`../lab/vars/k8s_staging.yml`](../lab/vars/k8s_staging.yml) / [`k8s_prod.yml`](../lab/vars/k8s_prod.yml) | Différences par environnement : namespace, couleur, réplicas (2 / 3), nodePort (30081 / 30082) |
| [`../lab/wordpress_k8s.yml`](../lab/wordpress_k8s.yml) + [`../lab/k8s-wordpress/`](../lab/k8s-wordpress/) | Étape 7 : WordPress (manifestes du TP 4.5) dans le namespace `blog`, Secret issu de **Vault** |

## Commandes et rôle

| Commande | Rôle |
|---|---|
| `sudo apt install -y python3-kubernetes` | bibliothèque Python utilisée par `kubernetes.core` |
| `ansible-galaxy collection list \| grep kubernetes.core` | collection installée (2.4.0) |
| `kubectl get nodes` | le contexte courant (`~/.kube/config`) doit être minikube |
| `export REDIS_PASSWORD=$(cat ~/.secrets/redis_k8s_prod)` | mot de passe Redis passé par variable d'environnement (en vrai : Vault ou credential Jenkins) |
| `ansible-playbook k8s_deploy.yml -e target_env=staging -e webapp_image=nedstudio/legeni-webapp -e app_version=1.0.0` | déploiement en staging |
| `… -e target_env=prod … -e app_version=2.0.0` | mise à jour de la prod |
| `… -e app_version=9.9.9` | déploiement raté → rollback automatique |
| `kubectl rollout history deployment/webapp -n legeni-prod` | historique des révisions |
| `kubectl get deploy webapp -n legeni-prod -o wide` | image actuellement déployée |
| `ansible-playbook wordpress_k8s.yml --vault-password-file .vault_pass` | étape 7 : WordPress sur Kubernetes par Ansible |

## Résultats obtenus
- **Staging** : `staging OK`, 2 réplicas, `{"env":"staging","version":"1.0.0"}`.
- **Prod 1.0.0** : `prod OK`, 3 réplicas.
- **Bug trouvé** : la mise à jour en 2.0.0 (version **valide**) a échoué et déclenché un rollback **à tort** : `Failed to execute on pod webapp-5458bd4c6-jf452 … pods "webapp-5458bd4c6-jf452" not found`. Le smoke test prenait « le premier Pod avec le label `app=webapp` » (`[0]`), qui était un **ancien Pod 1.0.0 en cours de suppression**.
  **Correction** : choisir un Pod `Running`, sans `deletionTimestamp`, dont l'image est la **nouvelle** version.
- **Prod 2.0.0** (après correction) : `prod OK`, `changed=1`, boucle de requêtes **0 erreur** pendant la mise à jour.
- **Version 9.9.9** : `Timed out waiting on resource` après 188 s → `Retour à la version précédente` → `Déploiement de 9.9.9 en prod échoué : rollback effectué`, **`failed=1 rescued=1`** ; image toujours `nedstudio/legeni-webapp:2.0.0` ; boucle : **356 réponses, 0 erreur**.
- **Idempotence** : relance en 2.0.0 → `changed=0` (namespace, Secret, manifestes inchangés ; smoke test `changed_when: false`).
- **Étape 7** : namespace `blog`, Secret créé depuis la variable chiffrée (24 caractères), MySQL et WordPress `1/1`, PVC `Bound`, page `WordPress › Installation` ; 2ᵉ passage `changed=0`.
- **Incident** : pendant l'étape 7, la VM a saturé (load average **35**, mémoire d'échange utilisée) avec staging + prod + legeni-dev + MySQL/WordPress en démarrage : WordPress affichait `Database Error`. Après suppression de l'environnement staging, tout est revenu à la normale. Leçon : **requests/limits et capacité du cluster** (TP 4.9) ne sont pas qu'une théorie.

## Réponses aux questions

**Quelles tâches sont `changed` à la 2ᵉ exécution ? Pourquoi le smoke test a-t-il `changed_when: false` ?** Aucune (`changed=0`) : les objets existent déjà dans l'état demandé. Le smoke test exécute une commande dans un Pod : sans `changed_when: false`, `k8s_exec` serait toujours `changed`, alors qu'un test **ne modifie rien** ; on garde ainsi un `PLAY RECAP` qui reflète les vrais changements.

**Rôle de l'annotation `checksum/config` ?** Elle dépend du contenu de la configuration (environnement, couleur). Si la ConfigMap change, l'annotation change, donc le modèle de Pod change : **rolling update automatique**, les Pods relisent leur configuration (sinon il faudrait un `rollout restart`, cf. TP 4.7).

**Jinja2 (ce TP) ou Kustomize (TP 4.12) ?** Les templates Jinja2 donnent toute la logique d'Ansible (conditions, boucles, variables, Vault) au même endroit que le déploiement ; Kustomize garde des manifestes **YAML valides** lisibles par `kubectl` seul, et Ansible peut les appliquer avec `lookup('kubernetes.core.kustomize', dir='k8s/overlays/prod')`. Pour le projet final : Kustomize pour les manifestes, Ansible pour l'orchestration (secrets Vault, attente, tests, rollback).
