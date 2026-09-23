# Fiche de suivi — Journal de bord automatique (Node-RED + Google Sheets)

_Bateau : Haku (Amel 50) · Projet supervision (Cerbo GX / Signal K / Node-RED)_
_**Statut : ✅ OPÉRATIONNEL (testé le 16/08/2026)** — reste la phase C (file d'attente hors-ligne)._
_Dernière mise à jour : 16/08/2026_

---

## 1. Objet
Remplir le **journal de bord automatiquement** à chaque navigation : départ, arrivée, distance, vitesses, vent, allure, nav de nuit, **moteur estimé** et **perf voile** — sans matériel supplémentaire. La ligne se pose **toute seule dans un Google Sheet**.

---

## 2. Architecture (le circuit complet)

```
Cerbo GX (Signal K + Node-RED)
   │  1. Node-RED lit Signal K toutes les 45 s (vent, vitesses, position, sonde)
   │  2. Détecte départ/arrivée, calcule la ligne (15 champs)
   │  3. À l'arrivée : POST JSON  ─────────►  Google Apps Script (doPost)
   │                                              │  ajoute la ligne
   │                                              ▼
   │                                        Google Sheet « Haku - Journal auto »
   │                                        onglet « Journal auto » (compte votre-compte@gmail.com)
   └─ 4. En parallèle : sauvegarde locale CSV + collecte polaires réelles
```

- **Aucune licence** (on a abandonné Power Automate car son déclencheur HTTP est Premium payant).
- Côté bateau : un seul envoi HTTP. Toute la logique est dans Node-RED.

---

## 3. Ce que le système produit
- **Google Sheet, onglet « Journal auto »** : 1 ligne par nav. Colonnes : Date · Départ (h + position) · Arrivée (h + position) · Vent direction · Vent force · Allure · Nav de nuit · Distance (MN) · Nombre de jours · Vitesse moyenne · Vitesse max · Moteur (estimé) · Heures moteur estimées · % au moteur · Perf voile (% polaire).
- **`/data/haku_journal.csv`** (Cerbo) : sauvegarde locale, même contenu (filet de sécurité).
- **`/data/haku_polaire_reelle.csv`** (Cerbo) : échantillons vent/vitesse à la voile → pour tracer tes **polaires réelles** vs théoriques.

---

## 4. Logique de détection

**Trajet**
- **Départ** = SOG > **1 kn** pendant **2 min** (`START_KN` / `START_MIN`).
- **Arrivée** = **immobilité réelle** pendant **5 min** : SOG < 0,5 kn **ET** position figée (déplacement < **0,1 MN**) **ET** profondeur < **60 m**.
  → **Anti-dérive** : encalminé qui dérive (position qui avance) ou au large en eau profonde = **le trajet ne se clôture pas**. Utilise `environment.depth.belowTransducer`.

**Moteur estimé** (ON si une condition ; basé sur la vitesse **surface**, donc la dérive n'est jamais comptée moteur)
- **A** : vent < 2,5 kn ET STW > 3,0 kn (assoupli pour le gennaker 180 m²).
- **B** : |angle vent| < 35° ET STW > 2 kn (zone morte).
- **C** : STW > **polaire VPP** × **1,15** + 0,3.

**Polaires** : table VPP Amel 50 (Berret-Racoupeau, 19-01-2017) intégrée, interpolation TWS × TWA. **Perf voile** = STW / polaire, moyennée hors moteur.

**Nuit** : SunCalc inline (soleil < −0,833°).

---

## 5. Réglages (nœud « Journal + moteur + polaire », en tête du code)

| Variable | Défaut | Rôle |
|---|---|---|
| `START_KN` / `START_MIN` | 1,0 kn / 2 min | seuil + durée du **départ** |
| `STOP_KN` / `STOP_MIN` | 0,5 kn / 5 min | seuil + durée de l'**arrivée** |
| `DEPTH_MAX` / `STOP_RADIUS` | 60 m / 0,1 MN | arrivée seulement si eau < 60 m **ET** immobile (anti-dérive) |
| `NOWIND_TWS` / `NOWIND_STW` | 2,5 / 3,0 kn | règle moteur A |
| `HIGH_TWA_DEG` / `HIGH_STW` | 35° / 2 kn | règle moteur B |
| `USE_RULE_C` / `C_MARGIN` | true / 1,15 | règle moteur C |

Throttle flash : sauvegarde « trajet en cours » toutes les **15 min** (+ transitions) ; échantillon polaire toutes les **2 min**.

---

## 6. Côté Cerbo — le flow Node-RED
- Fichier : **`HAKU_NodeRED_JournalBord_v1.json`** (dossier Journal de bord), onglet « HAKU - Journal de bord auto », 11 nœuds.
- Chaîne : `Poll 45s → GET Signal K (127.0.0.1:3000) → Journal + moteur + polaire →` [ `POST → Google Sheet` (URL /exec gravée) · `Ligne → journal.csv` · `Sauver trajet en cours` · `Échantillon → polaire_reelle.csv` ]. Branche démarrage : `Au démarrage → Lire trajet → Recharger trajet` (survit aux reboots).

## 7. Côté Google — le script
- Google Sheet **« Haku - Journal auto »** (compte **votre-compte@gmail.com**), onglet **« Journal auto »**.
- **Apps Script** (Extensions → Apps Script) : `setup()` crée/met en forme l'onglet ; `doPost(e)` reçoit le JSON et ajoute la ligne.
- Déployé en **Application Web** (Exécuter en tant que : Moi · Accès : **Tout le monde**) → **URL `/exec`** (collée dans le nœud Node-RED). Un GET navigateur affiche « doGet introuvable » = **normal** (on ne gère que le POST).

---

## 8. État / tests réalisés
- ✅ Logique validée en **simulation** (départ→moteur→voile→arrivée, dérive/sonde) avec le vrai code du flow.
- ✅ **Nav réelle 15/08** : départ détecté, « voile » confirmé à bord, lecture live OK (vent/STW/position/sonde).
- ✅ **Test POST 16/08** : lignes TEST bien arrivées dans le Google Sheet (circuit Cerbo → Node-RED → Sheet **validé**).
- ✅ Version **anti-dérive** déployée, `START_MIN = 2` confirmé.

---

## 9. Limites honnêtes
- **Moteur = estimé** : rate le **motorsailing** (moteur + voiles à vitesse plausible) → sous-compte les heures. Pour l'exact : câbler le **D+ alternateur → entrée numérique Cerbo** (plus tard).
- **Hors-ligne à l'arrivée** : si pas d'internet, le POST échoue → la nav est **seulement** dans le CSV local, **pas** dans le Sheet, et **pas de renvoi automatique** (à ajouter à la main). → résolu par la **phase C** ci-dessous.
- **CSV local jamais purgé** : il s'accumule (~90 Ko/an) — sans risque disque ; pas de doublon car le Sheet est alimenté en direct (on ne réimporte plus le CSV).

---

## 10. Reste à faire
- **Phase C (recommandée)** : file d'attente hors-ligne + **renvoi automatique** des navs quand internet revient (+ option purge/archivage du CSV local). → garantit qu'**aucune nav n'est perdue** même mouillé sans réseau.
- **Nettoyage** : supprimer le flux **Power Automate** (inutile) et l'onglet **« Journal auto » de l'Excel OneDrive** (tout est sur Google).
- **Moteur exact** (optionnel) : D+ alternateur → entrée Cerbo.
- **Polaires réelles** : après quelques semaines, exploiter `haku_polaire_reelle.csv` (nuage TWS/TWA/STW) et comparer au VPP.
- **Surveillance charge Cerbo** (RAM 1 Go = point sensible) : `uptime` / `free -m` / `top` en SSH ; possibilité d'un petit moniteur Node-RED.

---

## 11. Historique
- **14/08** : électrique/logiciel du feu de mouillage (contexte supervision).
- **15/08** : construction du flow journal (moteur estimé + polaires VPP + throttle), test en nav réelle ; onglet « Journal auto » créé dans l'Excel OneDrive (piste Power Automate).
- **16/08** : blocage Power Automate (Premium payant) → **bascule Google** (Sheet + Apps Script gratuit) ; ajout **anti-dérive** (immobilité + sonde) ; **circuit validé** par test POST. Notes `Note_Import_Journal_Auto_vers_Excel.md` et `PLAN_Demain_Journal_Google.md` = **remplacées par cette fiche**.

---

## 12. Fichiers de référence
- Flow : `HAKU_NodeRED_JournalBord_v1.json` (dossier Journal de bord).
- Polaires source : `Polaire/AMEL 50- polaires de vitesse - VPP 17-01-17.pdf`.
- Runtime Cerbo : `/data/haku_journal.csv`, `/data/haku_polaire_reelle.csv`, `/data/haku_trip_current.json`.
- Google : Sheet « Haku - Journal auto » (Drive de votre-compte@gmail.com) + script Apps Script associé.
