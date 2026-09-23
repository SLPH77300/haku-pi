#!/usr/bin/env bash
# =============================================================================
# Haku Pi — généré le 27/08/2026
# backup-flows.sh — sauvegarde quotidienne (haku-backup.timer, 04:10) et
# avant le reboot hebdomadaire.
#
# Copie vers /boot/firmware/haku-backup (partition FAT de la carte SD,
# lisible sur n'importe quel PC si le Pi est mort) :
#   - flows.json + settings.js (~/.node-red de l'utilisateur Node-RED)
#   - le contexte persistant (mode MOUILLAGE/MARINA, états d'alertes)
#   - /etc/haku/haku.env  ← CONTIENT DES SECRETS. Assumé : un accès physique
#     à la carte SD donne de toute façon accès à tout le système (voir README,
#     section Sécurité). Mettre BACKUP_INCLUDE_ENV=0 dans haku.env pour l'exclure.
#   - les journaux CSV
# Conserve les 7 dernières archives. Journal : journalctl -t haku-backup
# =============================================================================
set -euo pipefail

TAG="haku-backup"
ENV_FILE="/etc/haku/haku.env"
if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
fi

HAKU_USER="${HAKU_USER:-pi}"
USER_HOME="$(getent passwd "${HAKU_USER}" | cut -d: -f6)"
if [[ -z "${USER_HOME}" ]]; then
    logger -t "${TAG}" "Utilisateur ${HAKU_USER} introuvable, abandon"
    exit 1
fi

DEST_BASE="/boot/firmware/haku-backup"
if [[ ! -d /boot/firmware ]]; then
    DEST_BASE="/boot/haku-backup"   # anciennes images
fi
mkdir -p "${DEST_BASE}"

STAMP="$(date '+%Y%m%d-%H%M%S')"
WORK="$(mktemp -d /tmp/haku-backup.XXXXXX)"
trap 'rm -rf "${WORK}"' EXIT

copy_if_exists() {
    local src="$1" dst="$2"
    if [[ -e "${src}" ]]; then
        mkdir -p "$(dirname "${WORK}/${dst}")"
        cp -a "${src}" "${WORK}/${dst}"
    fi
}

copy_if_exists "${USER_HOME}/.node-red/flows.json"          "node-red/flows.json"
copy_if_exists "${USER_HOME}/.node-red/settings.js"         "node-red/settings.js"
copy_if_exists "${USER_HOME}/.node-red/package.json"        "node-red/package.json"
copy_if_exists "${USER_HOME}/.node-red/context"             "node-red/context"
copy_if_exists "/var/lib/haku/journal"                      "journal"
copy_if_exists "/var/lib/haku/alerts.log"                   "alerts.log"
# v1.1 : traces GPX + index carte + ports déclarés
copy_if_exists "${TRACKS_DIR:-/var/lib/haku/tracks}"        "tracks"
copy_if_exists "/var/lib/haku/ports.json"                   "ports.json"
if [[ "${BACKUP_INCLUDE_ENV:-1}" == "1" ]]; then
    copy_if_exists "${ENV_FILE}" "haku.env"
fi

ARCHIVE="${DEST_BASE}/haku-${STAMP}.tar.gz"
tar -czf "${ARCHIVE}" -C "${WORK}" .
sync

# --- Rotation : on garde les 7 plus récentes ---------------------------------
# Noms entièrement contrôlés (haku-AAAAMMJJ-HHMMSS.tar.gz), ls -1t est sûr ici.
# shellcheck disable=SC2012
mapfile -t OLD < <(ls -1t "${DEST_BASE}"/haku-*.tar.gz 2>/dev/null | tail -n +8)
for f in "${OLD[@]}"; do
    rm -f "${f}"
done

logger -t "${TAG}" "Sauvegarde OK : ${ARCHIVE} ($(du -h "${ARCHIVE}" | cut -f1))"
