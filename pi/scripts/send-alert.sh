#!/usr/bin/env bash
# =============================================================================
# Haku Pi — généré le 27/08/2026
# send-alert.sh <sujet> <corps>
#
# Envoi d'une alerte email via curl SMTP. Appelé par le flux Node-RED
# « 4 - Alertes » (nœud exec). Tous les paramètres viennent de
# /etc/haku/haku.env : AUCUN identifiant dans les flux Node-RED (les
# credentials des nœuds ne s'exportent pas dans flows.json — c'est le choix
# d'architecture documenté dans docs/ARCHITECTURE.md).
#
# Comportement :
#  - trace TOUJOURS l'alerte dans /var/lib/haku/alerts.log (persistant) ;
#  - si SMTP_HOST est vide → sortie 0 (pas une erreur : mode « dashboard +
#    alarmes VRM en secours », voir README) ;
#  - code retour ≠ 0 uniquement si l'envoi SMTP échoue vraiment.
# =============================================================================
set -euo pipefail

ENV_FILE="/etc/haku/haku.env"
LOG_DIR="/var/lib/haku"
LOG_FILE="${LOG_DIR}/alerts.log"

SUBJECT="${1:-Haku : alerte sans sujet}"
BODY="${2:-'(corps vide)'}"

# Charge la configuration si présente (les variables peuvent aussi venir de
# l'environnement systemd du service nodered).
if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
fi

# --- Trace locale persistante (quelques octets par alerte) -------------------
mkdir -p "${LOG_DIR}"
printf '%s | %s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${SUBJECT}" "${BODY}" >> "${LOG_FILE}"

# --- SMTP configuré ? --------------------------------------------------------
if [[ -z "${SMTP_HOST:-}" ]]; then
    logger -t haku-alert "SMTP non configuré, alerte tracée uniquement : ${SUBJECT}"
    exit 0
fi

SMTP_PORT="${SMTP_PORT:-587}"
SMTP_SECURITY="${SMTP_SECURITY:-starttls}"
SMTP_FROM="${SMTP_FROM:-haku-pi@localhost}"
SMTP_TO="${SMTP_TO:-}"

if [[ -z "${SMTP_TO}" ]]; then
    logger -t haku-alert "SMTP_TO vide : impossible d'envoyer « ${SUBJECT} »"
    exit 1
fi

# --- Construction du message (UTF-8, sujet encodé RFC 2047) ------------------
MAIL_FILE="$(mktemp /tmp/haku-alert.XXXXXX)"
trap 'rm -f "${MAIL_FILE}"' EXIT

SUBJECT_B64="$(printf '%s' "${SUBJECT}" | base64 -w0)"
{
    printf 'From: Haku Pi <%s>\r\n' "${SMTP_FROM}"
    printf 'To: %s\r\n' "${SMTP_TO}"
    printf 'Subject: =?UTF-8?B?%s?=\r\n' "${SUBJECT_B64}"
    printf 'Date: %s\r\n' "$(date -R)"
    printf 'MIME-Version: 1.0\r\n'
    printf 'Content-Type: text/plain; charset=UTF-8\r\n'
    printf 'Content-Transfer-Encoding: 8bit\r\n'
    printf '\r\n'
    printf '%s\r\n' "${BODY}"
    printf '\r\n-- \r\nHaku Pi (Raspberry Pi du bord) - %s\r\n' "$(hostname)"
} > "${MAIL_FILE}"

# --- Destinataires multiples (séparés par des virgules) ----------------------
RCPT_ARGS=()
IFS=',' read -ra RCPTS <<< "${SMTP_TO}"
for r in "${RCPTS[@]}"; do
    r="$(echo "${r}" | xargs)"   # trim
    [[ -n "${r}" ]] && RCPT_ARGS+=(--mail-rcpt "${r}")
done

# --- Choix du transport ------------------------------------------------------
# Pire cas total du script : 2 tentatives x 25 s + pause 15 s = 65 s,
# sous le timeout de 150 s du noeud exec Node-RED qui l'appelle.
CURL_ARGS=(
    --silent --show-error
    --connect-timeout 15 --max-time 25
    --mail-from "${SMTP_FROM}"
    "${RCPT_ARGS[@]}"
    --upload-file "${MAIL_FILE}"
)
case "${SMTP_SECURITY}" in
    ssl)      CURL_ARGS+=(--url "smtps://${SMTP_HOST}:${SMTP_PORT}") ;;
    starttls) CURL_ARGS+=(--url "smtp://${SMTP_HOST}:${SMTP_PORT}" --ssl-reqd) ;;
    none)     CURL_ARGS+=(--url "smtp://${SMTP_HOST}:${SMTP_PORT}") ;;
    *)        logger -t haku-alert "SMTP_SECURITY inconnu : ${SMTP_SECURITY}"; exit 1 ;;
esac
if [[ -n "${SMTP_USER:-}" && "${SMTP_USER}" != CHANGEME* ]]; then
    CURL_ARGS+=(--user "${SMTP_USER}:${SMTP_PASS:-}")
fi

# --- Envoi (une nouvelle tentative après 15 s en cas d'échec) ---------------
if curl "${CURL_ARGS[@]}"; then
    logger -t haku-alert "Alerte envoyée : ${SUBJECT}"
    exit 0
fi
sleep 15
if curl "${CURL_ARGS[@]}"; then
    logger -t haku-alert "Alerte envoyée (2e tentative) : ${SUBJECT}"
    exit 0
fi
logger -t haku-alert "ÉCHEC d'envoi SMTP : ${SUBJECT}"
exit 1
