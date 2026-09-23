#!/usr/bin/env bash
# =============================================================================
# Haku Pi — généré le 27/08/2026
# gen-adminauth.sh — génère le hash bcrypt du mot de passe de l'ÉDITEUR
# Node-RED et l'écrit dans /etc/haku/haku.env (variable NR_ADMIN_HASH).
#
# Usage :  sudo /opt/haku/scripts/gen-adminauth.sh
# Puis :   sudo systemctl restart nodered
#
# Le hash est calculé avec le module bcryptjs embarqué par Node-RED
# (même algorithme que « node-red admin hash-pw »). Le mot de passe n'apparaît
# jamais en clair sur le disque ni dans l'historique shell.
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

# --- Localisation de bcryptjs (fourni avec l'installation Node-RED) ----------
BCRYPT_DIR=""
for d in \
    /usr/lib/node_modules/node-red/node_modules \
    /usr/local/lib/node_modules/node-red/node_modules \
    "$(npm root -g 2>/dev/null || true)/node-red/node_modules"
do
    if [[ -n "${d}" && -d "${d}/bcryptjs" ]]; then
        BCRYPT_DIR="${d}"
        break
    fi
done
if [[ -z "${BCRYPT_DIR}" ]]; then
    echo "bcryptjs introuvable : Node-RED est-il installé (install.sh) ?" >&2
    exit 1
fi

# --- Saisie du mot de passe (masquée, avec confirmation) ---------------------
read -r -s -p "Nouveau mot de passe éditeur Node-RED : " PW1; echo
read -r -s -p "Confirmation : " PW2; echo
if [[ "${PW1}" != "${PW2}" ]]; then
    echo "Les deux saisies ne correspondent pas, abandon." >&2
    exit 1
fi
if [[ "${#PW1}" -lt 8 ]]; then
    echo "8 caractères minimum (bateau accessible via Tailscale !)." >&2
    exit 1
fi

# --- Hash bcrypt (coût 8, comme node-red admin hash-pw) ----------------------
HASH="$(HAKU_PW="${PW1}" NODE_PATH="${BCRYPT_DIR}" node -e \
    'console.log(require("bcryptjs").hashSync(process.env.HAKU_PW, 8))')"
unset PW1 PW2

# --- Écriture dans haku.env (via python3 : robuste face aux $ et / du hash) --
HAKU_NEW_HASH="${HASH}" python3 - "${ENV_FILE}" <<'PYEOF'
import os
import re
import sys

path = sys.argv[1]
new = os.environ["HAKU_NEW_HASH"]
with open(path, encoding="utf-8") as fh:
    content = fh.read()
line = "NR_ADMIN_HASH='" + new + "'"
if re.search(r"^NR_ADMIN_HASH=.*$", content, flags=re.M):
    content = re.sub(r"^NR_ADMIN_HASH=.*$", line, content, count=1, flags=re.M)
else:
    content = content.rstrip("\n") + "\n" + line + "\n"
with open(path, "w", encoding="utf-8") as fh:
    fh.write(content)
print("NR_ADMIN_HASH mis à jour dans " + path)
PYEOF

echo
echo "Hash bcrypt écrit. Prise en compte :  sudo systemctl restart nodered"
echo "Connexion éditeur : http://haku.local:1880/  (utilisateur : voir NR_ADMIN_USER)"
