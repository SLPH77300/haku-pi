#!/usr/bin/env bash
# =============================================================================
# Haku Pi — généré le 27/08/2026
# update.sh — met à jour l'installation Haku à partir du dépôt local.
#
# Usage :  sudo /opt/haku/scripts/update.sh [--palette]
#
#  1. sauvegarde préalable (backup-flows.sh) ;
#  2. si /opt/haku est un clone git : git pull ;
#  3. relance install.sh (idempotent : redéploie flows, settings, unités,
#     pare-feu, scripts…) ;
#  4. avec --palette : met aussi à jour @flowfuse/node-red-dashboard.
#
# NB : la mise à jour de Node-RED lui-même se fait en relançant le script
# officiel (voir README, section Mise à jour).
# =============================================================================
set -euo pipefail

REPO_DIR="/opt/haku"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Lancer avec sudo." >&2
    exit 1
fi

echo "== Sauvegarde préalable =="
"${REPO_DIR}/scripts/backup-flows.sh" || echo "(sauvegarde impossible, on continue)"

if [[ -d "${REPO_DIR}/.git" ]]; then
    echo "== git pull =="
    git -C "${REPO_DIR}" pull --ff-only
fi

if [[ "${1:-}" == "--palette" ]]; then
    ENV_FILE="/etc/haku/haku.env"
    HAKU_USER="pi"
    if [[ -f "${ENV_FILE}" ]]; then
        HAKU_USER="$(grep -E '^HAKU_USER=' "${ENV_FILE}" | tail -1 | cut -d= -f2 || true)"
        HAKU_USER="${HAKU_USER:-pi}"
    fi
    USER_HOME="$(getent passwd "${HAKU_USER}" | cut -d: -f6)"
    echo "== Mise à jour de la palette Dashboard 2.0 (${HAKU_USER}) =="
    sudo -u "${HAKU_USER}" bash -c \
        "cd '${USER_HOME}/.node-red' && npm update --no-audit --no-fund @flowfuse/node-red-dashboard"
fi

echo "== Redéploiement (install.sh idempotent) =="
bash "${REPO_DIR}/install.sh"

echo "== Terminé. État des services : =="
systemctl --no-pager --lines=0 status nodered haku-healthcheck.timer || true
