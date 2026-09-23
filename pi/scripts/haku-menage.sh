#!/bin/bash
# =============================================================================
# haku-menage.sh — Haku Pi (15/09/2026)
# 1) retire les tuiles sans capteur (T° batterie, Baro, T° air)
# 2) installe Leaflet 1.9.4 dans /opt/haku/static/leaflet (carte des navigations)
# 3) redémarre Node-RED
# 4) importe l'historique des navs depuis le Google Sheet (lien en argument)
#    ou depuis ~/journal_export.csv s'il existe.
# Usage : bash ~/haku-menage.sh ["https://docs.google.com/spreadsheets/d/ID/edit#gid=G"]
# Réexécutable sans risque (idempotent). Sauvegarde du flux avant modif.
# =============================================================================
set -u
SHEET_URL="${1:-}"

echo "== 1/4 Menage des tuiles sans capteur =="
cp ~/.node-red/flows.json ~/.node-red/flows.json.bak.$(date +%s)
python3 - <<'PY'
import json,os
p=os.path.expanduser('~/.node-red/flows.json'); d=json.load(open(p))
REMOVE={'t_temp','t_i_baro','t_i_tair'}
n0=len(d); d[:]=[n for n in d if n.get('id') not in REMOVE]
for n in d:
    w=n.get('wires')
    if isinstance(w,list): n['wires']=[[x for x in g if x not in REMOVE] for g in w]
json.dump(d,open(p,'w'),ensure_ascii=False,indent=4); json.load(open(p))
print('tuiles retirees :', n0-len(d), '(0 = deja fait)')
PY

echo "== 2/4 Leaflet 1.9.4 (carte) =="
LV=1.9.4; T=/tmp/leaflet.$$; mkdir -p "$T/images"; OK=1
for f in leaflet.js leaflet.css; do
  curl -fsSL "https://unpkg.com/leaflet@$LV/dist/$f" -o "$T/$f" || { echo "ECHEC $f"; OK=0; }
done
for f in marker-icon.png marker-icon-2x.png marker-shadow.png layers.png layers-2x.png; do
  curl -fsSL "https://unpkg.com/leaflet@$LV/dist/images/$f" -o "$T/images/$f" || echo "ECHEC image $f"
done
if [ "$OK" = 1 ] && [ -s "$T/leaflet.js" ] && [ -s "$T/leaflet.css" ]; then
  sudo mkdir -p /opt/haku/static && sudo rm -rf /opt/haku/static/leaflet \
  && sudo mv "$T" /opt/haku/static/leaflet && sudo chown -R root:root /opt/haku/static/leaflet \
  && echo "Leaflet installe : $(ls /opt/haku/static/leaflet | tr '\n' ' ')"
else
  echo "Leaflet NON installe (pas d'Internet ?) — la carte restera vide"; rm -rf "$T"
fi

echo "== 3/4 Redemarrage Node-RED =="
sudo systemctl restart nodered && echo "nodered redemarre"

echo "== 4/4 Import de l'historique des navs =="
CSV=""
if [ -n "$SHEET_URL" ]; then
  ID=$(echo "$SHEET_URL" | sed -n 's#.*/spreadsheets/d/\([^/?]*\).*#\1#p')
  GID=$(echo "$SHEET_URL" | sed -n 's#.*gid=\([0-9]*\).*#\1#p'); GID=${GID:-0}
  if [ -z "$ID" ]; then echo "Lien Google Sheet non reconnu"; else
    curl -fsSL "https://docs.google.com/spreadsheets/d/$ID/export?format=csv&gid=$GID" -o /tmp/journal_export.csv
    if head -c 300 /tmp/journal_export.csv | grep -qi "date"; then CSV=/tmp/journal_export.csv
    else echo "Telechargement KO : la feuille n'est pas partagee en lecture par lien (Partager -> Tout utilisateur disposant du lien : Lecteur)"; fi
  fi
elif [ -f ~/journal_export.csv ]; then CSV=~/journal_export.csv
fi
if [ -n "$CSV" ]; then
  echo "--- apercu ---"; head -3 "$CSV"; echo "--- simulation ---"
  python3 /opt/haku/scripts/import-journal.py "$CSV" --dry-run && \
  python3 /opt/haku/scripts/import-journal.py "$CSV"
else
  echo "Pas d'import : relance avec le lien du Google Sheet en argument, ou depose ~/journal_export.csv"
fi
echo "== TERMINE == (recharge le tableau de bord : Ctrl+F5, page Navigations)"
