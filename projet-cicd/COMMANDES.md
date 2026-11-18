# Projet CI/CD – Chaîne complète « du commit à la production »

**Dépôt du projet :** https://github.com/nedstudio237-cmd/legeni-webapp (rapport : [`docs/rapport.md`](https://github.com/nedstudio237-cmd/legeni-webapp/blob/main/docs/rapport.md))
**Statut :** ✅ lots 0 à 5 réalisés, 3 scénarios de soutenance démontrés – preuves dans [`preuves/`](preuves/)
**Restent :** webhook GitHub (relais smee.io, à valider) et e-mail Gmail (`outils/configurer-email.sh`)

## 🧠 À mémoriser

| Commande | À quoi elle sert |
|---|---|
| `git checkout -b feature/x` → `git push -u origin feature/x` → PR → merge | seul chemin vers `main` (protégée, build vert obligatoire) |
| `docker build --target test .` | lance flake8 + pytest dans l'étape `test` du Dockerfile |
| `docker run --rm -i hadolint/hadolint < Dockerfile` / `trivy image --severity CRITICAL --ignore-unfixed` | qualité du Dockerfile / failles de l'image |
| `ansible-playbook provision.yml -K` (×2 → `changed=0`) | installe Docker, Minikube, Jenkins ; idempotence |
| `ansible-vault encrypt vars/vault.yml` | secrets chiffrés dans Git |
| `ansible-playbook deploy.yml -e target_env=staging -e app_version=1.1.0-14 --vault-password-file …` | déploiement Kubernetes + smoke test + rollback automatique |
| `kubectl rollout history deployment/webapp -n legeni-prod` | révisions (preuve du rollback) |
| `while true; do curl -s $(minikube ip):30082/api/info; sleep 0.5; done` | mesure « 0 erreur » pendant une mise à jour |

## Lots réalisés

| Lot | Réalisation | Preuve |
|---|---|---|
| 0 – Git | `main` protégée, une branche `feature/*` + PR par fonctionnalité (PR #7 à #15), tags `v1.0.0`, `v1.1.0` créés par Jenkins | GitHub |
| 1 – Docker | multi-stage (test → runtime), `appuser`, HEALTHCHECK, CMD exec, hadolint 0, Trivy 0 CRITICAL, tag `<VERSION>-<build>` | `lot5_console_main14.txt` |
| 2 – Ansible | `provision.yml` + rôles `docker`, `minikube`, `jenkins` ; 2ᵉ passage `changed=0` ; `vars/vault.yml` chiffré | — |
| 3 – Kubernetes | `deploy.yml` : staging (2 réplicas, 30081) / prod (3, 30082), Redis StatefulSet + PVC, Secret, probes, ressources, `maxUnavailable: 0`, smoke test, rollback | `lot3_*.txt`, `final_*.txt` |
| 4 – CI | multibranch ; qualité en parallèle (tests + couverture **83,64 %**, flake8, hadolint, syntaxe Ansible) ; Trivy ; rapports JUnit/couverture/warnings ; credentials `registry-credentials`, `kubeconfig`, `ansible-vault-pass` | `lot5_stage_view_main14.txt` |
| 5 – CD | `main` : push → staging → `input` → prod → tag ; branches/PR jamais déployées ; e-mail en cas d'échec | `lot5_console_main10.txt` |

## Scénario de soutenance

| Scénario | Résultat | Preuve |
|---|---|---|
| 1. Couleur + VERSION 1.1.0 | PR verte sans déploiement → staging → validation → prod `1.1.0-12`, **0 erreur / 363 requêtes** | `scenario1_boucle_prod_1.1.0.txt` |
| 2. Test qui échoue | rouge à « Tests », aucune image, prod inchangée | `scenario2_console_test_casse.txt` |
| 3. readinessProbe cassée | `Timed out` → rollback automatique → build rouge ; prod et staging servis (0 erreur / 513) | `scenario3_*.txt` |

## Problèmes résolus
- 3 erreurs pendant le 1ᵉʳ rolling update → **`preStop: sleep 5`** → 0 erreur ensuite.
- Ansible dans Jenkins ne trouvait pas la lib `kubernetes` → `ansible_python_interpreter: "{{ ansible_playbook_python }}"`.
