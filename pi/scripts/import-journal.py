#!/usr/bin/env python3
# =============================================================================
# Haku Pi — généré le 27/08/2026 (v1.1.0)
# import-journal.py — importe l'HISTORIQUE du journal de bord dans le Pi.
#
# Sources acceptées :
#   - export CSV du Cerbo (/data/haku_journal.csv du flow « Journal auto »)
#   - export CSV du Google Sheet « Haku - Journal auto » (ou journal manuel)
#   - XLSX si openpyxl est installé (sinon : exporter la feuille en CSV)
#
# Usage :
#   python3 import-journal.py FICHIER.csv [FICHIER2.csv ...] [--dry-run]
#
# Tolérant : séparateur ; ou , détecté, noms de colonnes FR variés, positions
# en degrés décimaux (43.275 / 43,275) OU deg-minutes (43°16.5'N, 43 16,5 N).
# Dédoublonnage par horodatage de départ. Ajoute au JSONL puis reconstruit
# l'index carte (tracks-index.py).
# =============================================================================
import csv
import io
import json
import os
import re
import subprocess
import sys
import unicodedata
from datetime import datetime, timezone

JOURNAL_JSONL = os.environ.get(
    "JOURNAL_JSONL", "/var/lib/haku/journal/haku_journal.jsonl")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Colonne source (normalisée) -> clé canonique du journal Haku (15 champs)
COLUMN_MAP = {
    "date": "depart_ts", "date depart": "depart_ts", "depart": "depart_ts",
    "heure depart": "_heure_depart", "date arrivee": "arrivee_ts",
    "arrivee": "arrivee_ts", "heure arrivee": "_heure_arrivee",
    "port depart": "port_depart", "de": "port_depart", "origine": "port_depart",
    "port arrivee": "port_arrivee", "a": "port_arrivee", "vers": "port_arrivee",
    "destination": "port_arrivee",
    "position depart": "_pos_depart", "pos depart": "_pos_depart",
    "lat depart": "lat_depart", "lon depart": "lon_depart",
    "position arrivee": "_pos_arrivee", "pos arrivee": "_pos_arrivee",
    "lat arrivee": "lat_arrivee", "lon arrivee": "lon_arrivee",
    "distance": "distance_nm", "distance nm": "distance_nm", "nm": "distance_nm",
    "duree": "duree_h", "duree h": "duree_h",
    "vitesse moy": "sog_moy_kn", "sog moy": "sog_moy_kn",
    "vitesse max": "sog_max_kn", "sog max": "sog_max_kn",
    "vent moy": "tws_moy_kn", "tws moy": "tws_moy_kn",
    "vent max": "tws_max_kn", "tws max": "tws_max_kn", "rafale": "tws_max_kn",
    "vent dir": "twd_moy", "direction vent": "twd_moy", "twd": "twd_moy",
}

DEGMIN_RE = re.compile(
    r"""^\s*(?P<deg>\d{1,3})\s*[°d\s]\s*(?P<min>\d{1,2}(?:[.,]\d+)?)\s*['’m]?\s*
        (?P<hemi>[NSEWnsewOo])?\s*$""", re.X)
DEC_RE = re.compile(r"^\s*(?P<sign>[-+]?)(?P<val>\d{1,3}(?:[.,]\d+)?)\s*(?P<hemi>[NSEWnsewOo])?\s*$")


def norm(s):
    """minuscule, sans accents, espaces simples — pour matcher les colonnes."""
    s = unicodedata.normalize("NFD", str(s))
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"[\s_/()\-]+", " ", s).strip().lower()


def parse_coord(text, is_lon=False):
    """Une coordonnée : degrés décimaux OU deg-minutes, hémisphère optionnel."""
    if text is None:
        return None
    t = str(text).strip()
    if not t:
        return None
    m = DEGMIN_RE.match(t)
    if m:
        val = float(m.group("deg")) + float(m.group("min").replace(",", ".")) / 60.0
        hemi = (m.group("hemi") or "").upper()
        if hemi in ("S",) or (hemi in ("W", "O") and is_lon):
            val = -val
        return round(val, 6)
    m = DEC_RE.match(t)
    if m:
        val = float(m.group("val").replace(",", "."))
        if m.group("sign") == "-":
            val = -val
        hemi = (m.group("hemi") or "").upper()
        if hemi == "S" or (hemi in ("W", "O") and is_lon):
            val = -abs(val)
        return round(val, 6)
    return None


def parse_position(text):
    """« 43°16.5'N 5°21.2'E » ou « 43.275, 5.353 » -> (lat, lon)."""
    if not text:
        return (None, None)
    t = str(text).strip()
    # séparation : virgule (si pas décimale ambiguë), point-virgule ou espace médian
    parts = re.split(r"\s*[;/]\s*", t)
    if len(parts) != 2:
        parts = re.split(r",\s*(?=[-+0-9])", t)
    if len(parts) != 2:
        halves = re.split(r"\s+(?=\d{1,3}\s*[°d])", t, maxsplit=1)
        parts = halves if len(halves) == 2 else None
    if not parts or len(parts) != 2:
        return (None, None)
    return (parse_coord(parts[0], is_lon=False), parse_coord(parts[1], is_lon=True))


def parse_ts(date_txt, heure_txt=None):
    """dd/mm/yyyy [hh:mm], yyyy-mm-dd..., ISO -> ISO UTC (naïf = heure locale bord)."""
    if not date_txt:
        return None
    t = str(date_txt).strip()
    if heure_txt:
        t += " " + str(heure_txt).strip()
    t = t.replace("T", " ").replace("Z", "").strip()
    fmts = ["%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M", "%d/%m/%Y",
            "%d/%m/%y %H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M",
            "%Y-%m-%d", "%d-%m-%Y %H:%M", "%d.%m.%Y %H:%M"]
    for f in fmts:
        try:
            return datetime.strptime(t, f).replace(tzinfo=timezone.utc).isoformat()
        except ValueError:
            continue
    return None


def to_num(v):
    try:
        return float(str(v).replace(",", ".").replace("kn", "").replace("NM", "").strip())
    except (TypeError, ValueError):
        return None


def read_rows(path):
    """Liste de dicts depuis un CSV (délimiteur auto) ou un XLSX (openpyxl)."""
    if path.lower().endswith((".xlsx", ".xls")):
        try:
            import openpyxl  # noqa: facultatif
        except ImportError:
            sys.exit("XLSX non supporté ici (openpyxl absent) : "
                     "exporter la feuille en CSV puis relancer.")
        wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
        ws = wb.active
        rows = list(ws.iter_rows(values_only=True))
        if not rows:
            return []
        header = [str(c) if c is not None else "" for c in rows[0]]
        return [dict(zip(header, r)) for r in rows[1:]]
    # Encodage : les exports Excel/Google Sheets FR sont souvent en
    # Windows-1252 — on tente UTF-8 (BOM tolere) puis cp1252 puis latin-1.
    raw = None
    with open(path, "rb") as fh:
        data = fh.read()
    for enc in ("utf-8-sig", "cp1252", "latin-1"):
        try:
            raw = data.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    if raw is None:
        sys.exit("Encodage du fichier illisible (essaye : UTF-8, cp1252, latin-1) : "
                 + path)
    sample = raw[:4096]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=";,\t")
    except csv.Error:
        dialect = csv.excel
        dialect.delimiter = ";" if sample.count(";") >= sample.count(",") else ","
    return list(csv.DictReader(io.StringIO(raw, newline=""), dialect=dialect))


def convert_row(raw):
    """Une ligne source -> entrée canonique du journal (ou None)."""
    e, extra = {}, {}
    for col, val in raw.items():
        if col is None or val is None or str(val).strip() == "":
            continue
        key = COLUMN_MAP.get(norm(col))
        if key:
            e[key] = val
        else:
            extra[norm(col).replace(" ", "_")] = str(val).strip()

    out = {"source": "import"}
    out["depart_ts"] = parse_ts(e.get("depart_ts"), e.get("_heure_depart"))
    out["arrivee_ts"] = parse_ts(e.get("arrivee_ts"), e.get("_heure_arrivee")) \
        or out["depart_ts"]
    if not out["depart_ts"]:
        return None
    for k in ("port_depart", "port_arrivee"):
        if e.get(k):
            out[k] = str(e[k]).strip()
    if "_pos_depart" in e:
        out["lat_depart"], out["lon_depart"] = parse_position(e["_pos_depart"])
    if "_pos_arrivee" in e:
        out["lat_arrivee"], out["lon_arrivee"] = parse_position(e["_pos_arrivee"])
    for k in ("lat_depart", "lon_depart", "lat_arrivee", "lon_arrivee"):
        if e.get(k) is not None and out.get(k) is None:
            out[k] = parse_coord(e[k], is_lon="lon" in k)
    for k in ("distance_nm", "duree_h", "sog_moy_kn", "sog_max_kn",
              "tws_moy_kn", "tws_max_kn"):
        if e.get(k) is not None:
            n = to_num(e[k])
            if n is not None:
                out[k] = n
    if e.get("twd_moy"):
        out["twd_moy"] = str(e["twd_moy"]).strip()
    out.update(extra)
    return {k: v for k, v in out.items() if v is not None}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    if not args:
        sys.exit("Usage : import-journal.py FICHIER.csv [...] [--dry-run]")

    existing = set()
    if os.path.exists(JOURNAL_JSONL):
        with open(JOURNAL_JSONL, encoding="utf-8") as fh:
            for line in fh:
                try:
                    existing.add(json.loads(line).get("depart_ts"))
                except (json.JSONDecodeError, AttributeError):
                    continue

    imported, skipped, invalid = [], 0, 0
    for path in args:
        for raw in read_rows(path):
            entry = convert_row(raw)
            if entry is None:
                invalid += 1
                continue
            if entry["depart_ts"] in existing:
                skipped += 1
                continue
            existing.add(entry["depart_ts"])
            imported.append(entry)

    print("Import : {} nouvelles navs, {} doublons ignorés, {} lignes invalides"
          .format(len(imported), skipped, invalid))
    if dry:
        for e in imported:
            print("  ", json.dumps(e, ensure_ascii=False))
        return 0
    if imported:
        os.makedirs(os.path.dirname(JOURNAL_JSONL), exist_ok=True)
        with open(JOURNAL_JSONL, "a", encoding="utf-8") as fh:
            for e in imported:
                fh.write(json.dumps(e, ensure_ascii=False) + "\n")
    # Reconstruction de l'index carte
    subprocess.run([sys.executable, os.path.join(SCRIPT_DIR, "tracks-index.py")],
                   check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
