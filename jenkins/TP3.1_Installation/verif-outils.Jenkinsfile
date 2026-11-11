pipeline {
    agent any
    stages {
        stage('Outils') {
            steps {
                sh 'docker version --format "Docker serveur : {{.Server.Version}}"'
                sh 'docker compose version'
                sh 'kubectl version --client'
                sh 'ansible --version | head -1'
                sh 'id'
            }
        }
    }
}
