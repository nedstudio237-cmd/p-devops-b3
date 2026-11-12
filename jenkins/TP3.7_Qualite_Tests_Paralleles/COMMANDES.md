# TP 3.7 – Projet Qualité : tests en parallèle, rapports et quality gates

**Objectif :** transformer le pipeline en **contrôle qualité automatique** : tests unitaires avec rapport et couverture minimale, analyse statique du code et du Dockerfile, scan de vulnérabilités. Chaque contrôle peut faire échouer le build (*quality gate*).

**Statut :** ✅ réalisé et vérifié (défi compris) – preuves dans [`preuves/`](preuves/)
**Branche utilisée :** [`qualite`](https://github.com/nedstudio237-cmd/legeni-webapp/tree/qualite) du dépôt `legeni-webapp` (la branche `main` est protégée : les essais qui cassent volontairement le build sont faits sur une branche dédiée).

## Fichiers réalisés

| Fichier | Contenu |
|---|---|
| [`Jenkinsfile.qualite`](Jenkinsfile.qualite) | Pipeline du TP + défi : 4 contrôles **en parallèle** (tests, lint Python, lint Dockerfile, secrets), build, scan Trivy |
| [`job-legeni-qualite.xml`](job-legeni-qualite.xml) | Job *Pipeline script from SCM* : branche `*/qualite`, Script Path `Jenkinsfile.qualite` |
| [`gitleaksignore.txt`](gitleaksignore.txt) | Contenu du `.gitleaksignore` (empreinte du faux jeton du défi) |

## Commandes et rôle

### Notions du Jenkinsfile
| Élément | Rôle |
|---|---|
| `parallel { stage(…) stage(…) }` | Lance plusieurs stages **en même temps** → pipeline plus rapide |
| `agent { docker { image 'python:3.12-slim'; args '-e HOME=/tmp'; reuseNode true } }` | Exécute un stage dans un **conteneur jetable** (Python) sur le même workspace, sans installer Python dans Jenkins |
| `python -m venv /tmp/venv` + `pip install -r requirements.txt -r requirements-dev.txt` | Environnement Python isolé avec les dépendances de test |
| `pytest --junitxml=reports/junit.xml --cov=app --cov-report=xml:reports/coverage.xml --cov-fail-under=80` | Tests + rapport JUnit + rapport de couverture ; **échoue si couverture < 80 %** |
| `flake8 --output-file=reports/flake8.txt --tee .` | Analyse statique du code Python (style, erreurs), résultat dans un fichier et à l'écran |
| `docker run --rm -i hadolint/hadolint:v2.12.0 < Dockerfile` | Analyse statique du Dockerfile (bonnes pratiques) |
| `gitleaks detect --source . --no-banner --redact -v` | Défi : cherche des secrets dans tout l'historique Git |
| `docker run … aquasec/trivy:0.57.1 image --severity CRITICAL --ignore-unfixed --exit-code 1 $IMAGE:$VERSION` | Scan de vulnérabilités : échoue si CRITICAL corrigeable |
| `junit 'reports/junit.xml'` | Publie le rapport de tests (**Test Result**, courbe de tendance) |
| `recordCoverage(tools: [[parser: 'COBERTURA', pattern: 'reports/coverage.xml']])` | Publie la couverture (**Coverage Report**) |
| `recordIssues(tools: [flake8(pattern: 'reports/flake8.txt')])` | Publie les alertes flake8 (**Flake8 Warnings**) |
| `post { always { … } }` (dans le stage) | Publie les rapports **même si le stage échoue** |
| `post { cleanup { cleanWs() } }` | Vide le workspace à la fin |

### Git (essais des quality gates, branche `qualite`)
| Commande | Rôle |
|---|---|
| `git checkout -b qualite` / `git push -u origin qualite` | Branche dédiée aux essais |
| `git commit -am "…" && git push` | Pousse une modification qui doit casser un contrôle |
| `git revert --no-edit HEAD && git push` | Annule la modification (retour au vert) |
| `git rm config_test.ini` + `.gitleaksignore` | Retire le faux secret et déclare son empreinte comme connue |

## Résultats obtenus
- **Build #1 (vert)** : les 3 contrôles démarrent au même instant (+6 s) ; Test Result **6/6** ; couverture **83,64 %** ; Flake8 **0** alerte ; hadolint OK ; Trivy `Total: 0 (CRITICAL: 0)`.
- **Les 4 quality gates déclenchés (puis annulés) :**

| Modification | Stage en échec | Message obtenu |
|---|---|---|
| ligne de 147 caractères dans `app.py` (build #2) | Lint Python | `E501 line too long (147 > 100 characters)` |
| fonction `statistiques()` de 15 lignes sans test (build #3) | Tests unitaires | `Required test coverage of 80% not reached. Total coverage: 67.14%` |
| `FROM python:latest` (build #4) | Lint Dockerfile | `DL3007 … Using latest is prone to errors` |
| `FROM python:3.12.0-slim` (build #6) | Scan de sécurité | `Total: 13 (CRITICAL: 13)` |

  *Adaptation porte 4 : avec `python:3.6-slim` (build #5, demandé par le TP), c'est le stage **Build image** qui échoue (`No matching distribution found for flask==3.1.0` : Flask 3.1 n'existe pas pour Python 3.6), donc le scan n'est jamais atteint. On a utilisé une image Python 3.12 ancienne (2023) non corrigée, qui se construit mais contient 13 vulnérabilités critiques.*
- **Défi Secrets** : build #7 vert (`no leaks found`) ; la clé `AKIAIOSFODNN7EXAMPLE` du TP n'est **pas** détectée (build #8 vert : c'est la clé d'exemple officielle d'AWS, ignorée volontairement par gitleaks) ; une fausse clé au format réaliste est détectée (build #9 rouge, `RuleID: aws-access-token`, `leaks found: 1`) ; build #10 vert après suppression + `.gitleaksignore`.

## Réponses aux questions

**Pourquoi publier les rapports dans `post { always { … } }` plutôt qu'à la fin de `steps` ?** Si les tests échouent, la commande `pytest` renvoie une erreur et les `steps` s'arrêtent : les instructions suivantes ne seraient jamais exécutées. Or c'est justement quand ça échoue qu'on a le plus besoin du rapport. `post { always }` s'exécute dans tous les cas.

**UNSTABLE (jaune) vs FAILURE (rouge) ?** **FAILURE** : le build n'a pas pu aller au bout (commande en erreur, quality gate bloquante). **UNSTABLE** : le build est allé au bout mais un indicateur de qualité n'est pas bon (ex. des tests en échec dans le rapport). Le plugin **JUnit** met le build en **jaune** quand le rapport contient des tests en échec alors que l'étape qui les a lancés n'a pas elle-même fait échouer le build (par exemple `pytest … || true`, ou un outil qui produit le rapport sans code d'erreur).

## À retenir
- **Parallèle** = plusieurs contrôles en même temps ; le build attend la fin de tous et échoue si l'un échoue.
- **Agent Docker** = outils dans des conteneurs jetables, Jenkins reste léger.
- **Quality gates** : couverture minimale, lint du code et du Dockerfile, scan de vulnérabilités, recherche de secrets : chacun peut bloquer la livraison.
- Un secret commité reste dans l'**historique Git** : il faut le **révoquer**, pas seulement supprimer le fichier.
