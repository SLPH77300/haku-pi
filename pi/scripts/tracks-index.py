#!/usr/bin/env python3
# =============================================================================
# Haku Pi — généré le 27/08/2026 (v1.1.0)
# tracks-index.py — consolide les traces GPX + le journal de bord en UN
# fichier index.geojson pour la carte « Navigations » du dashboard.
#
# Entrées :
#   - ${TRACKS_DIR}/*.gpx                (traces écrites par le flux « Traces »)
#   - ${JOURNAL_JSONL}                   (lignes JSON du journal de bord :
#                                         POST /journal du Cerbo + import-journal.py)
# Sortie (écriture atomique) :
#   - ${TRACKS_DIR}/index.geojson : FeatureCollection
#       * LineString par trace (props : fichier, ts, nm, saison, + fiche
#         journal si une nav correspond à ± 3 h)
#       * Point par nav du journal SANS trace (historique importé)
#       * membre « stats » : NM total, nb navs, par saison
#
# Appelé par : le flux Node-RED (clôture de trace, POST /journal) et
# import-journal.py. Aucune dépendance hors bibliothèque standard.
# =============================================================================
import json
import math
import os
import re
import sys
import tempfile
from datetime import datetime, timezone

TRACKS_DIR = os.environ.get("TRACKS_DIR", "/var/lib/haku/tracks")
JOURNAL_JSONL = os.environ.get(
    "JOURNAL_JSONL", "/var/lib/haku/journal/haku_journal.jsonl")
LINK_WINDOW_H = 3.0   # écart max trace <-> entrée journal (heures)

TRKPT_RE = re.compile(
    r'<trkpt\s+lat="(?P<lat>[-0-9.]+)"\s+lon="(?P<lon>[-0-9.]+)"\s*>'
    r'(?:.*?<time>(?P<time>[^<]+)</time>)?.*?</trkpt>',
    re.S)


def haversine_nm(lat1, lon1, lat2, lon2):
    """Distance en milles nautiques entre deux points."""
    r_nm = 3440.065
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r_nm * math.asin(min(1, math.sqrt(a)))


def parse_iso(ts):
    """Datetime UTC depuis une chaîne ISO (tolère 'Z' et l'absence de tz)."""
    if not ts:
        return None
    try:
        t = str(ts).strip().replace("Z", "+00:00")
        d = datetime.fromisoformat(t)
        if d.tzinfo is None:
            d = d.replace(tzinfo=timezone.utc)
        return d
    except ValueError:
        return None


def parse_gpx(path):
    """Extrait (points [(lat, lon, ts)], nm, start, end) d'un fichier GPX.
    Defensif : un fichier corrompu/illisible renvoie None, un point invalide
    (non numerique, NaN/inf, hors bornes) est ignore — la carte ne doit
    jamais se figer a cause d'un fichier abime."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            content = fh.read()
    except OSError:
        return None
    pts = []
    for m in TRKPT_RE.finditer(content):
        try:
            lat = float(m.group("lat"))
            lon = float(m.group("lon"))
        except (TypeError, ValueError):
            continue
        if not (math.isfinite(lat) and math.isfinite(lon)):
            continue
        if abs(lat) > 90 or abs(lon) > 180:
            continue
        ts = parse_iso(m.group("time"))
        pts.append((lat, lon, ts))
    if len(pts) < 2:
        return None
    nm = sum(haversine_nm(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1])
             for i in range(len(pts) - 1))
    times = [p[2] for p in pts if p[2] is not None]
    return {
        "points": pts,
        "nm": round(nm, 1),
        "start": min(times) if times else None,
        "end": max(times) if times else None,
    }


def load_journal():
    entries = []
    if not os.path.exists(JOURNAL_JSONL):
        return entries
    with open(JOURNAL_JSONL, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(e, dict):
                continue  # ligne valide JSON mais pas un objet : ignoree
            e["_depart"] = parse_iso(e.get("depart_ts"))
            e["_arrivee"] = parse_iso(e.get("arrivee_ts"))
            entries.append(e)
    return entries


def season_of(dt):
    return str(dt.year) if dt else "inconnue"


def journal_props(e):
    """Les champs « fiche » exposés dans la popup de la carte."""
    keep = {}
    for k, v in e.items():
        if k.startswith("_") or v in (None, ""):
            continue
        keep[k] = v
    return keep


def build_index():
    features = []
    used_journal = set()
    journal = load_journal()

    gpx_files = sorted(
        f for f in os.listdir(TRACKS_DIR)
        if f.endswith(".gpx")) if os.path.isdir(TRACKS_DIR) else []

    total_nm = 0.0
    per_season = {}

    for fname in gpx_files:
        parsed = parse_gpx(os.path.join(TRACKS_DIR, fname))
        if not parsed:
            continue
        start, end = parsed["start"], parsed["end"]
        props = {
            "type": "trace",
            "fichier": fname,
            "nm": parsed["nm"],
            "depart_ts": start.isoformat() if start else None,
            "arrivee_ts": end.isoformat() if end else None,
            "saison": season_of(start),
        }
        # Lien avec une entrée du journal (± LINK_WINDOW_H autour du départ)
        if start:
            best, best_dt = None, LINK_WINDOW_H * 3600
            for i, e in enumerate(journal):
                if i in used_journal or not e["_depart"]:
                    continue
                dt = abs((e["_depart"] - start).total_seconds())
                if dt < best_dt:
                    best, best_dt = i, dt
            if best is not None:
                used_journal.add(best)
                props.update(journal_props(journal[best]))
                props["journal"] = True
        coords = [[round(p[1], 5), round(p[0], 5)] for p in parsed["points"]]
        features.append({
            "type": "Feature",
            "geometry": {"type": "LineString", "coordinates": coords},
            "properties": props,
        })
        total_nm += parsed["nm"]
        s = props["saison"]
        per_season.setdefault(s, {"navs": 0, "nm": 0.0})
        per_season[s]["navs"] += 1
        per_season[s]["nm"] += parsed["nm"]

    # Navs du journal SANS trace GPX (historique importé) -> marqueurs Point
    for i, e in enumerate(journal):
        if i in used_journal:
            continue
        lat = e.get("lat_arrivee", e.get("lat_depart"))
        lon = e.get("lon_arrivee", e.get("lon_depart"))
        if lat is None or lon is None:
            continue
        props = {"type": "nav_journal", "saison": season_of(e["_depart"])}
        props.update(journal_props(e))
        features.append({
            "type": "Feature",
            "geometry": {"type": "Point",
                         "coordinates": [round(float(lon), 5), round(float(lat), 5)]},
            "properties": props,
        })
        nm = 0.0
        try:
            nm = float(e.get("distance_nm") or 0)
        except (TypeError, ValueError):
            nm = 0.0
        total_nm += nm
        s = props["saison"]
        per_season.setdefault(s, {"navs": 0, "nm": 0.0})
        per_season[s]["navs"] += 1
        per_season[s]["nm"] += nm

    for s in per_season.values():
        s["nm"] = round(s["nm"], 1)

    return {
        "type": "FeatureCollection",
        "generated": datetime.now(timezone.utc).isoformat(),
        "stats": {
            "navs": len(features),
            "nm_total": round(total_nm, 1),
            "saisons": per_season,
        },
        "features": features,
    }


def main():
    # En cas d'ECHEC quel qu'il soit, l'ancien index.geojson reste en place
    # (ecriture temporaire + rename atomique, jamais de troncature directe).
    try:
        os.makedirs(TRACKS_DIR, exist_ok=True)
        index = build_index()
        out = os.path.join(TRACKS_DIR, "index.geojson")
        fd, tmp = tempfile.mkstemp(dir=TRACKS_DIR, suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                # allow_nan=False : un NaN residuel ferait echouer ICI (index
                # precedent conserve) plutot que de casser le JSON cote carte.
                json.dump(index, fh, ensure_ascii=False, allow_nan=False)
            os.chmod(tmp, 0o644)  # lisible par Node-RED/httpStatic et backups
            os.replace(tmp, out)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    except Exception as exc:  # noqa: BLE001 — filet volontaire, trace + index intact
        print("tracks-index: ECHEC ({}) — index precedent conserve".format(exc),
              file=sys.stderr)
        return 1
    print("index.geojson : {} features, {} NM".format(
        index["stats"]["navs"], index["stats"]["nm_total"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
