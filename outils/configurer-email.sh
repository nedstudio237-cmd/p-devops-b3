#!/bin/bash
# TP 3.8 étape 7 : configure l'envoi d'e-mails de Jenkins (Gmail) puis provoque un échec pour recevoir la notification.
# Prérequis : ~/.secrets/gmail  (ligne 1 : adresse Gmail, ligne 2 : mot de passe d'application de 16 lettres)
#   Créer le mot de passe d'application : https://myaccount.google.com/apppasswords (validation en 2 étapes requise)
set -euo pipefail
JENKINS=${JENKINS_URL:-http://localhost:8080}
U=$(sed -n 1p ~/.secrets/jenkins); T=$(sed -n 2p ~/.secrets/jenkins)
MAIL=$(sed -n 1p ~/.secrets/gmail); PASS=$(sed -n 2p ~/.secrets/gmail | tr -d ' ')
[ -n "$MAIL" ] && [ ${#PASS} -eq 16 ] || { echo "~/.secrets/gmail : adresse puis code de 16 lettres attendus" >&2; exit 1; }

echo "1) Credential gmail-smtp + Extended E-mail Notification (smtp.gmail.com:465, SSL)"
curl -sf -u "$U:$T" "$JENKINS/scriptText" --data-urlencode "script=
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import hudson.plugins.emailext.*
def store = SystemCredentialsProvider.getInstance().getStore()
store.getCredentials(Domain.global()).findAll { it.id == 'gmail-smtp' }.each { store.removeCredentials(Domain.global(), it) }
store.addCredentials(Domain.global(), new UsernamePasswordCredentialsImpl(CredentialsScope.GLOBAL, 'gmail-smtp', 'Gmail SMTP (TP 3.8)', '$MAIL', '$PASS'))
def acc = new MailAccount()
acc.setSmtpHost('smtp.gmail.com'); acc.setSmtpPort('465'); acc.setUseSsl(true); acc.setCredentialsId('gmail-smtp')
def d = jenkins.model.Jenkins.get().getDescriptorByType(ExtendedEmailPublisherDescriptor)
d.setMailAccount(acc); d.setDefaultReplyTo('$MAIL'); d.save()
def loc = jenkins.model.JenkinsLocationConfiguration.get(); loc.setAdminAddress('Jenkins TP <$MAIL>'); loc.save()
println 'configuration e-mail OK'"

echo "2) Branche test/echec-email avec un test qui échoue volontairement"
cd ~/legeni-webapp
git checkout -q main && git pull -q
git checkout -qB test/echec-email
printf '\n\ndef test_echec_volontaire():\n    assert False, "échec volontaire (TP 3.8 : notification e-mail)"\n' >> tests/test_app.py
git commit -qam "TP 3.8 : échec volontaire pour tester la notification e-mail"
git push -qf -u origin test/echec-email
curl -sf -u "$U:$T" -X POST "$JENKINS/job/legeni-webapp-mb/build?delay=0" -o /dev/null

J="$JENKINS/job/legeni-webapp-mb/job/test%252Fechec-email/lastBuild"
echo "3) Attente du build (rouge attendu)…"
sleep 20
until curl -sf -u "$U:$T" "$J/api/json?tree=building" | grep -q '"building":false'; do sleep 5; done
curl -s -u "$U:$T" "$J/consoleText" > ~/tp-devops-b3/jenkins/TP3.8_Deploiement_Continu/preuves/07_console_echec_notification.txt
grep -E "Email was triggered|Sending email|Successfully created MimeMessage|Error|Finished" \
  ~/tp-devops-b3/jenkins/TP3.8_Deploiement_Continu/preuves/07_console_echec_notification.txt | tail -6

echo "4) Nettoyage : suppression de la branche de test"
git checkout -q main && git branch -qD test/echec-email && git push -q origin --delete test/echec-email
echo "→ Vérifie ta boîte $MAIL : « ❌ Échec legeni-webapp-mb/test%2Fechec-email #1 »"
