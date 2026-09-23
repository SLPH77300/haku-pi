#!/usr/bin/env bash
# =============================================================================
# Haku Pi — v1.2.0
# gen-grafana-pass.sh — change le mot de passe admin de Grafana et le
# mémorise dans /etc/haku/haku.env (variable GRAFANA_ADMIN_PASS).
# Même patron que gen-adminauth.sh (éditeur Node-RED).
#
# Usage :  sudo /opt/haku/scripts/gen-grafana-pass.sh
#
# NB : install.sh génère déjà un mot de passe aléatoire au premier lancement ;
# ce script sert à le remplacer par un mot de passe choisi.
# =============================================================================
set -euo pipefail

ENV_FILE="/etc/haku/haku.env"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Ce script doit être lancé avec sudo (il modifie ${ENV_FILE})." >&2
    exit 1
fi
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "${ENV_FILE} introuvable : lancer d'abord install.sh." >&2
    exit 1
fi
if ! command -v grafana-cli > /dev/null 2>&1; then
    echo "grafana-cli introuvable : Grafana est-il installé (GRAFANA_ENABLED=1 + install.sh) ?" >&2
    exit 1
fi

# --- Saisie (masquée, avec confirmation) -------------------------------------
read -r -s -p "Nouveau mot de passe admin Grafana : " PW1; echo
read -r -s -p "Confirmation : " PW2; echo
if [[ "${PW1}" != "${PW2}" ]]; then
    echo "Les deux saisies ne correspondent pas, abandon." >&2
    exit 1
fi
if [[ "${#PW1}" -lt 8 ]]; then
    echo "8 caractères minimum (Grafana accessible via Tailscale !)." >&2
    exit 1
fi

# --- Application dans Grafana (base sqlite locale) ---------------------------
grafana-cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini \
    admin reset-admin-password "${PW1}" > /dev/null
systemctl restart grafana-server

# --- Mémorisation dans haku.env (via python3 : robuste face aux $ et /) ------
HAKU_NEW_PASS="${PW1}" python3 - "${ENV_FILE}" <<'PYEOF'
import os
import re
import sys

path = sys.argv[1]
new = os.environ["HAKU_NEW_PASS"]
with open(path, encoding="utf-8") as fh:
    content = fh.read()
line = "GRAFANA_ADMIN_PASS='" + new.replace("'", "'\\''") + "'"
if re.search(r"^GRAFANA_ADMIN_PASS=.*$", content, flags=re.M):
    content = re.sub(r"^GRAFANA_ADMIN_PASS=.*$", line, content, count=1, flags=re.M)
else:
    content = content.rstrip("\n") + "\n" + line + "\n"
with open(path, "w", encoding="utf-8") as fh:
    fh.write(content)
print("GRAFANA_ADMIN_PASS mis à jour dans " + path)
PYEOF
unset PW1 PW2

echo
echo "Mot de passe admin Grafana appliqué (service redémarré)."
echo "Connexion : http://haku.local:3001/  (utilisateur : admin)"
