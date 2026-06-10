// ============================================================
//  Jenkinsfile — Flask App CI/CD Pipeline
//  Repo    : https://github.com/Raghusadhu/flask-cicd-app.git
//  Server  : 192.168.132.52 (user: raghu)
//  Agent   : Jenkins built-in node
//  Envs    : Pre-Production (port 5001) → Production (port 5000)
// ============================================================

pipeline {

    agent { label 'built-in' }

    environment {
        APP_NAME    = "flask-cicd-app"
        TARGET_HOST = "192.168.132.52"
        DEPLOY_USER = "raghu"

        // Credential stored in Jenkins as:
        // Kind: SSH Username with private key  OR  Username with password
        // ID: raghu-ssh-key
        DEPLOY_CREDS = credentials('2410b96b-ae3d-484a-90da-5d8f70f2e61c')
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
        disableConcurrentBuilds()
    }

    stages {

        // ── 1. Checkout ──────────────────────────────────────
        stage('Checkout') {
            steps {
                echo "Checking out source code..."
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: "git rev-parse --short HEAD",
                        returnStdout: true
                    ).trim()
                    env.BUILD_LABEL = "${env.APP_NAME}-${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                    echo "Build Label: ${env.BUILD_LABEL}"
                }
            }
        }

        // ── 2. Setup Python venv ─────────────────────────────
        stage('Setup Environment') {
            steps {
                echo "Setting up Python virtual environment..."
                sh '''
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install --upgrade pip -q
                    pip install -r requirements.txt -q
                    echo "Dependencies installed."
                '''
            }
        }

        // ── 3. Lint ──────────────────────────────────────────
        stage('Lint') {
            steps {
                echo "Running flake8 linter..."
                sh '''
                    . venv/bin/activate
                    pip install flake8 -q
                    flake8 app/ --max-line-length=120 --exclude=venv || true
                '''
            }
        }

        // ── 4. Unit Tests ─────────────────────────────────────
        stage('Unit Tests') {
            steps {
                echo "Running unit tests..."
                sh '''
                    . venv/bin/activate
                    pytest tests/ \
                        --cov=app \
                        --cov-report=xml:coverage.xml \
                        --junitxml=test-results.xml \
                        -v
                '''
            }
            post {
                always {
                    junit 'test-results.xml'
                }
            }
        }

        // ── 5. Build Artifact ─────────────────────────────────
        stage('Build Artifact') {
            steps {
                echo "Packaging application..."
                sh '''
                    tar --exclude='.git' \
                        --exclude='venv' \
                        --exclude='__pycache__' \
                        --exclude='*.pyc' \
                        -czf ${BUILD_LABEL}.tar.gz \
                        app/ requirements.txt scripts/
                    echo "Artifact: ${BUILD_LABEL}.tar.gz"
                    ls -lh ${BUILD_LABEL}.tar.gz
                '''
                archiveArtifacts artifacts: "${env.BUILD_LABEL}.tar.gz", fingerprint: true
            }
        }

        // ── 6. Deploy → Pre-Production ────────────────────────
        stage('Deploy to Pre-Prod') {
            steps {
                echo "Deploying to Pre-Production on ${env.TARGET_HOST}:5001 ..."
                sh """
                    sshpass -p \${DEPLOY_CREDS_PSW} scp \
                        -o StrictHostKeyChecking=no \
                        \${BUILD_LABEL}.tar.gz \
                        \${DEPLOY_USER}@\${TARGET_HOST}:/tmp/

                    sshpass -p \${DEPLOY_CREDS_PSW} ssh \
                        -o StrictHostKeyChecking=no \
                        \${DEPLOY_USER}@\${TARGET_HOST} \
                        "set -e
                         mkdir -p /home/raghu/flask-app/preprod
                         tar -xzf /tmp/\${BUILD_LABEL}.tar.gz -C /home/raghu/flask-app/preprod/
                         chmod +x /home/raghu/flask-app/preprod/scripts/deploy.sh
                         bash /home/raghu/flask-app/preprod/scripts/deploy.sh preprod \${BUILD_NUMBER}
                         echo '[PreProd] Deployment done.'"
                """
            }
        }

        // ── 7. Smoke Test Pre-Prod ────────────────────────────
        stage('Smoke Test Pre-Prod') {
            steps {
                echo "Smoke testing Pre-Production..."
                sh """
                    sleep 5
                    RESPONSE=\$(curl -sf --max-time 10 http://\${TARGET_HOST}:5001/health || echo "FAIL")
                    echo "Response: \$RESPONSE"
                    if echo "\$RESPONSE" | grep -q 'healthy'; then
                        echo "Pre-Prod smoke test PASSED"
                    else
                        echo "Pre-Prod smoke test FAILED"
                        exit 1
                    fi
                """
            }
        }

        // ── 8. Manual Approval Gate ───────────────────────────
        stage('Approval: Promote to Production') {
            steps {
                timeout(time: 60, unit: 'MINUTES') {
                    input(
                        message: "Deploy build ${env.BUILD_LABEL} to PRODUCTION?",
                        ok: 'Approve & Deploy'
                    )
                }
                echo "Production deployment approved."
            }
        }

        // ── 9. Deploy → Production ────────────────────────────
        stage('Deploy to Production') {
            steps {
                echo "Deploying to Production on ${env.TARGET_HOST}:5000 ..."
                sh """
                    sshpass -p \${DEPLOY_CREDS_PSW} scp \
                        -o StrictHostKeyChecking=no \
                        \${BUILD_LABEL}.tar.gz \
                        \${DEPLOY_USER}@\${TARGET_HOST}:/tmp/

                    sshpass -p \${DEPLOY_CREDS_PSW} ssh \
                        -o StrictHostKeyChecking=no \
                        \${DEPLOY_USER}@\${TARGET_HOST} \
                        "set -e
                         mkdir -p /home/raghu/flask-app/prod
                         tar -xzf /tmp/\${BUILD_LABEL}.tar.gz -C /home/raghu/flask-app/prod/
                         chmod +x /home/raghu/flask-app/prod/scripts/deploy.sh
                         bash /home/raghu/flask-app/prod/scripts/deploy.sh prod \${BUILD_NUMBER}
                         echo '[Prod] Deployment done.'"
                """
            }
        }

        // ── 10. Smoke Test Production ─────────────────────────
        stage('Smoke Test Production') {
            steps {
                echo "Smoke testing Production..."
                sh """
                    sleep 5
                    RESPONSE=\$(curl -sf --max-time 10 http://\${TARGET_HOST}:5000/health || echo "FAIL")
                    echo "Response: \$RESPONSE"
                    if echo "\$RESPONSE" | grep -q 'healthy'; then
                        echo "Production smoke test PASSED"
                    else
                        echo "Production smoke test FAILED"
                        exit 1
                    fi
                """
            }
        }

        // ── 11. Cleanup ───────────────────────────────────────
        // cleanWs() must be in a stage, NOT in post {}
        // post{} runs outside agent context and breaks cleanWs
        stage('Cleanup') {
            steps {
                echo "Cleaning up Jenkins workspace..."
                cleanWs()
            }
        }

    } // end stages

    // ════════════════════════════════════════════════════════
    //  POST — email hardcoded (env vars don't expand here)
    // ════════════════════════════════════════════════════════
    post {
        success {
            echo "PIPELINE SUCCESS — deployed to Pre-Prod and Prod."
            mail(
                to      : 'raghu.sadhu84@gmail.com',
                subject : "SUCCESS: flask-cicd-app #${env.BUILD_NUMBER} deployed to Production",
                body    : "Build ${env.BUILD_NUMBER} deployed successfully.\n\nBuild URL: ${env.BUILD_URL}"
            )
        }
        failure {
            echo "PIPELINE FAILED — check logs at: ${env.BUILD_URL}"
            mail(
                to      : 'raghu.sadhu84@gmail.com',
                subject : "FAILED: flask-cicd-app #${env.BUILD_NUMBER} pipeline failure",
                body    : "Build ${env.BUILD_NUMBER} failed.\n\nCheck logs at: ${env.BUILD_URL}"
            )
        }
    }

} // end pipeline