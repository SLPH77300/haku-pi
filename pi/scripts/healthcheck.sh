#!/usr/bin/env bash
# =============================================================================
# Haku Pi — généré le 27/08/2026
# healthcheck.sh — lancé par haku-healthcheck.timer toutes les 2 minutes.
#
# Vérifie que Node-RED répond sur http://127.0.0.1:1880/health.
#  - 3 tentatives espacées de 15 s ;
#  - en échec : systemctl restart nodered ;
#  - si 5 contrôles CONSÉCUTIFS ont nécessité un restart sans succès,
#    reboot du Pi (au plus une fois par jour, et jamais dans les 30 premières
#    minutes après le boot) — le watchdog matériel couvre les gels plus durs.
#
# État runtime dans /run/haku (tmpfs, remis à zéro à chaque boot).
# Journal : journalctl -t haku-healthcheck
# =============================================================================
set -euo pipefail

URL="http://127.0.0.1:1880/health"
STATE_DIR="/run/haku"
FAIL_FILE="${STATE_DIR}/healthcheck-failures"
REBOOT_STAMP="/var/lib/haku/last-healthcheck-reboot"
MAX_FAILURES_BEFORE_REBOOT=5
TAG="haku-healthcheck"

mkdir -p "${STATE_DIR}"

check_once() {
    curl --silent --fail --max-time 10 --output /dev/null "${URL}"
}

ok() {
    # Succès : remise à zéro du compteur d'échecs.
    rm -f "${FAIL_FILE}"
    exit 0
}

# --- 3 tentatives ------------------------------------------------------------
for attempt in 1 2 3; do
    if check_once; then
        [[ "${attempt}" -gt 1 ]] && logger -t "${TAG}" "OK après ${attempt} tentatives"
        ok
    fi
    [[ "${attempt}" -lt 3 ]] && sleep 15
done

# --- Échec confirmé : restart Node-RED ---------------------------------------
failures=0
[[ -f "${FAIL_FILE}" ]] && failures="$(cat "${FAIL_FILE}")"
failures=$((failures + 1))
echo "${failures}" > "${FAIL_FILE}"
logger -t "${TAG}" "Node-RED ne répond pas (échec n°${failures}) : restart nodered"
systemctl restart nodered || logger -t "${TAG}" "restart nodered a échoué"

# --- Escalade éventuelle vers un reboot --------------------------------------
if [[ "${failures}" -ge "${MAX_FAILURES_BEFORE_REBOOT}" ]]; then
    uptime_s="$(cut -d. -f1 /proc/uptime)"
    if [[ "${uptime_s}" -lt 1800 ]]; then
        logger -t "${TAG}" "Reboot souhaité mais uptime < 30 min : on attend"
        exit 0
    fi
    now="$(date +%s)"
    last=0
    [[ -f "${REBOOT_STAMP}" ]] && last="$(cat "${REBOOT_STAMP}")"
    if (( now - last < 86400 )); then
        logger -t "${TAG}" "Reboot souhaité mais déjà rebooté il y a < 24 h : on attend"
        exit 0
    fi
    mkdir -p "$(dirname "${REBOOT_STAMP}")"
    echo "${now}" > "${REBOOT_STAMP}"
    logger -t "${TAG}" "Node-RED KO ${failures} fois d'affilée : REBOOT du Pi"
    systemctl reboot
fi
exit 0
