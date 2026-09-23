#!/usr/bin/env bash
# =============================================================================
# Haku Pi — v1.2.0
# heartbeat.sh — lancé par haku-heartbeat.timer toutes les 10 minutes.
#
# Heartbeat « dead-man » (D) : pinger HEALTHCHECK_URL (healthchecks.io ou
# équivalent) UNIQUEMENT si le Pi va bien. La logique est inversée par
# rapport aux alertes classiques : c'est le SILENCE qui alerte.
#  - HEALTHCHECK_URL vide (défaut)      → sortie 0, rien ne part ;
#  - /health local ne répond pas        → PAS de ping (Node-RED mort ⇒ le
#    service externe verra le trou et alertera par email/push) ;
#  - le ping lui-même échoue (WAN down) → tracé dans le journal, sortie 0
#    (là aussi, le service externe fait son travail).
# Data : un GET de quelques centaines d'octets toutes les 10 min — négligeable
# même sur la SIM.
# =============================================================================
set -euo pipefail

ENV_FILE="/etc/haku/haku.env"
TAG="haku-heartbeat"

if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
fi

URL="${HEALTHCHECK_URL:-}"
if [[ -z "${URL}" || "${URL}" == CHANGEME* ]]; then
    exit 0
fi

# On ne pingue PAS si Node-RED est mort : le silence déclenche l'alerte externe.
if ! curl --silent --fail --max-time 10 --output /dev/null http://127.0.0.1:1880/health; then
    logger -t "${TAG}" "/health local KO : pas de ping (l'alerte externe fera son travail)"
    exit 0
fi

if curl --silent --fail --max-time 20 --output /dev/null "${URL}"; then
    exit 0
fi
logger -t "${TAG}" "ping ${URL} en échec (WAN coupé ?) — le service externe alertera"
exit 0
