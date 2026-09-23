#!/usr/bin/env bash
# =============================================================================
# Haku Pi — généré le 27/08/2026
# kiosk.sh — lancé par l'unité utilisateur haku-kiosk.service, elle-même
# démarrée par ~/.config/labwc/autostart (ou wayfire.ini) après l'autologin.
#
# 1. attend que le dashboard Node-RED réponde (jusqu'à 3 min, puis lance
#    quand même : Chromium affichera sa page d'erreur et la supervision
#    systemd relancera le tout) ;
# 2. lance Chromium en mode kiosk plein écran, cache disque en RAM (/tmp).
#
# Si Chromium se ferme/plante, systemd --user le relance (Restart=always).
# =============================================================================
set -euo pipefail

KIOSK_URL="${KIOSK_URL:-http://127.0.0.1:1880/dashboard/haku}"
CACHE_DIR="/tmp/haku-chromium-cache"

# --- Attente du dashboard (max 180 s) ----------------------------------------
for _ in $(seq 1 90); do
    if curl --silent --fail --max-time 3 --output /dev/null "${KIOSK_URL}"; then
        break
    fi
    sleep 2
done

# --- Choix du binaire Chromium (nom différent selon les images Pi OS) --------
CHROMIUM=""
for bin in chromium-browser chromium; do
    if command -v "${bin}" > /dev/null 2>&1; then
        CHROMIUM="${bin}"
        break
    fi
done
if [[ -z "${CHROMIUM}" ]]; then
    echo "kiosk.sh : chromium introuvable (sudo apt install chromium)" >&2
    sleep 30   # évite une boucle de restart trop rapide
    exit 1
fi

mkdir -p "${CACHE_DIR}"

ARGS=(
    --kiosk
    --noerrdialogs
    --disable-infobars
    --no-first-run
    --disable-session-crashed-bubble
    --disable-features=Translate
    --check-for-update-interval=31536000
    --disk-cache-dir="${CACHE_DIR}"
    --disk-cache-size=52428800
    --overscroll-history-navigation=0
    --autoplay-policy=no-user-gesture-required
)
# Sous Wayland (labwc/wayfire), force le backend natif ; sous X11 on n'ajoute rien.
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    ARGS+=(--ozone-platform=wayland)
fi

exec "${CHROMIUM}" "${ARGS[@]}" "${KIOSK_URL}"
