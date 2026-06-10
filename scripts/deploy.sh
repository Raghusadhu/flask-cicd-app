#!/bin/bash
# deploy.sh — Deploy Flask app to the given environment (preprod | prod)
# Usage: ./deploy.sh <preprod|prod> <build_number>

set -euo pipefail

# ─── Arguments ───────────────────────────────────────────────────────────────
ENV="${1:-}"
BUILD_NUMBER="${2:-unknown}"

if [[ -z "$ENV" ]]; then
    echo "[ERROR] Usage: $0 <preprod|prod> <build_number>"
    exit 1
fi

if [[ "$ENV" != "preprod" && "$ENV" != "prod" ]]; then
    echo "[ERROR] Environment must be 'preprod' or 'prod'. Got: $ENV"
    exit 1
fi

# ─── Config ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/${ENV}.env"
APP_DIR="/opt/flask-app/${ENV}"
VENV_DIR="$APP_DIR/venv"
LOG_DIR="/var/log/flask-app/${ENV}"
PID_FILE="/var/run/flask-app/${ENV}.pid"
SERVICE_NAME="flask-app-${ENV}"
APP_USER="raghu"

echo "=============================================="
echo " Flask App Deployment"
echo " Environment : $ENV"
echo " Build       : $BUILD_NUMBER"
echo " Timestamp   : $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# ─── Load env variables ──────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
    echo "[ERROR] Environment file not found: $ENV_FILE"
    exit 1
fi
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
echo "[INFO] Loaded config from $ENV_FILE"

# ─── Prepare directories ─────────────────────────────────────────────────────
echo "[INFO] Preparing directories..."
sudo mkdir -p "$APP_DIR" "$LOG_DIR" "$(dirname "$PID_FILE")"
sudo chown -R "$APP_USER":"$APP_USER" "$APP_DIR" "$LOG_DIR"

# ─── Copy application files ──────────────────────────────────────────────────
echo "[INFO] Copying application files..."
sudo rsync -av --exclude='venv' --exclude='__pycache__' --exclude='*.pyc' \
    "$SCRIPT_DIR/../app/" "$APP_DIR/app/"
sudo cp "$SCRIPT_DIR/../requirements.txt" "$APP_DIR/"

# ─── Set up Python virtual environment ───────────────────────────────────────
echo "[INFO] Setting up virtual environment..."
if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
fi
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
pip install --upgrade pip -q
pip install -r "$APP_DIR/requirements.txt" -q
echo "[INFO] Dependencies installed."

# ─── Stop existing service ───────────────────────────────────────────────────
echo "[INFO] Stopping existing service (if running)..."
if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    sudo systemctl stop "$SERVICE_NAME"
    echo "[INFO] Stopped $SERVICE_NAME"
else
    echo "[INFO] $SERVICE_NAME was not running."
fi

# ─── Write systemd unit file ─────────────────────────────────────────────────
echo "[INFO] Writing systemd unit file..."
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=Flask App - ${ENV}
After=network.target

[Service]
User=${APP_USER}
WorkingDirectory=${APP_DIR}/app
EnvironmentFile=${ENV_FILE}
ExecStart=${VENV_DIR}/bin/gunicorn -w ${GUNICORN_WORKERS} -b 0.0.0.0:${PORT} app:app \
    --access-logfile ${LOG_DIR}/access.log \
    --error-logfile ${LOG_DIR}/error.log \
    --pid ${PID_FILE}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"

# ─── Start service ───────────────────────────────────────────────────────────
echo "[INFO] Starting $SERVICE_NAME..."
sudo systemctl start "$SERVICE_NAME"
sleep 3

# ─── Health check ────────────────────────────────────────────────────────────
echo "[INFO] Running health check..."
HEALTH_URL="http://localhost:${PORT}/health"
MAX_RETRIES=5
COUNT=0

until curl -sf "$HEALTH_URL" > /dev/null; do
    COUNT=$((COUNT + 1))
    if [[ $COUNT -ge $MAX_RETRIES ]]; then
        echo "[ERROR] Health check FAILED after $MAX_RETRIES attempts. Rolling back..."
        sudo systemctl stop "$SERVICE_NAME"
        exit 1
    fi
    echo "[WARN] Health check attempt $COUNT failed. Retrying in 5s..."
    sleep 5
done

echo "[SUCCESS] Deployment to $ENV completed successfully!"
echo "[INFO] App is running at $HEALTH_URL"
