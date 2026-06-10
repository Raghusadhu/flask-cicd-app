# Flask App — Jenkins CI/CD Pipeline
## Pre-Production → Production Deployment

---

## 📁 Project Structure

```
flask-cicd-project/
├── Jenkinsfile              ← Main pipeline definition
├── requirements.txt         ← Python dependencies
├── app/
│   └── app.py               ← Flask application
├── tests/
│   └── test_app.py          ← Pytest unit tests
└── scripts/
    ├── deploy.sh            ← Deployment script (runs on target server)
    ├── preprod.env          ← Pre-Prod environment config
    └── prod.env             ← Production environment config
```

---

## 🔄 Pipeline Flow

```
Code Push to main
       │
       ▼
  1. Checkout
       │
       ▼
  2. Setup Python venv + install deps
       │
       ▼
  3. Lint (flake8)
       │
       ▼
  4. Unit Tests + Coverage Report
       │
       ▼
  5. Build Artifact (.tar.gz)
       │
       ▼
  6. Deploy → Pre-Production (SSH + deploy.sh)
       │
       ▼
  7. Smoke Test PreProd (/health check)
       │
       ▼
  8. ⏸ Manual Approval Gate
       │
       ▼
  9. Deploy → Production (SSH + deploy.sh)
       │
       ▼
 10. Smoke Test Production (/health check)
       │
       ▼
  Email Notification (Success / Failure)
```

---

## ⚙️ Jenkins Setup Steps

### 1. Install Required Plugins
- Git Plugin
- Pipeline Plugin
- GitHub Integration Plugin
- HTML Publisher Plugin (for coverage report)
- Email Extension Plugin

### 2. Add SSH Credentials
Go to: **Manage Jenkins → Credentials → Global → Add Credentials**

| ID                | Type              | Description          |
|-------------------|-------------------|----------------------|
| `preprod-ssh-key` | SSH Username + Key| PreProd server access|
| `prod-ssh-key`    | SSH Username + Key| Prod server access   |

### 3. Create Jenkins Pipeline Job
1. New Item → Pipeline
2. Under **Build Triggers**: check **GitHub hook trigger for GITScm polling**
3. Under **Pipeline**: choose **Pipeline script from SCM**
4. SCM: Git → enter your repo URL
5. Script Path: `Jenkinsfile`
6. Save & Build

### 4. Configure GitHub Webhook
In GitHub repo → Settings → Webhooks → Add webhook:
- Payload URL: `http://<jenkins-host>:8080/github-webhook/`
- Content type: `application/json`
- Events: **Just the push event**

---

## 🌍 Environment Details

| Property        | Pre-Production         | Production             |
|-----------------|------------------------|------------------------|
| Host            | preprod.internal.co    | prod.internal.co       |
| Port            | 5001                   | 5000                   |
| Workers         | 2                      | 4                      |
| Log Level       | WARNING                | ERROR                  |
| Health URL      | :5001/health           | :5000/health           |

---

## 🚀 Deploy Script Behaviour

`scripts/deploy.sh <env> <build_number>` does the following:
1. Loads the correct `.env` config file
2. Prepares app directory on target server
3. Sets up Python virtual environment
4. Installs dependencies via pip
5. Stops existing systemd service (if running)
6. Writes a new systemd unit file with correct config
7. Starts the service via gunicorn
8. Runs `/health` endpoint check with retries
9. Rolls back (stops service) if health check fails

---

## 📋 Key Design Decisions

| Decision | Reason |
|---|---|
| Manual approval gate before Prod | Prevents accidental pushes to production |
| Health check with retries | Gives app time to start before marking as failed |
| Build artifact as `.tar.gz` | Consistent, versioned artifact transferred via SCP |
| systemd service management | Production-grade process management with auto-restart |
| `cleanWs()` in post | Keeps Jenkins agent disk clean |
