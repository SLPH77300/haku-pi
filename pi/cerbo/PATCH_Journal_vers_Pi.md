# PATCH Cerbo — « Journal vers Pi »

> Haku Pi — généré le 27/08/2026 (v1.1.0)

Objectif : le flow **« Journal de bord auto »** qui tourne déjà dans le
Node-RED du Cerbo (Venus OS Large, opérationnel depuis le 16/08) envoie une
**copie** de chaque ligne de navigation (15 champs) au Raspberry Pi, en plus
de ses sorties existantes (Google Sheet + CSV locaux `/data/haku_journal.csv`
et `/data/haku_polaire_reelle.csv`, qui ne changent pas et restent le filet
de sécurité).

Le Pi archive la ligne dans `/var/lib/haku/journal/haku_journal.jsonl` et met
à jour la carte « Navigations » (lien automatique avec la trace GPX dont le
départ est à ± 3 h).

Principe : **le Pi consomme, le Cerbo ne porte rien de plus** — 2 nœuds,
fire-and-forget, timeout 3 s, aucun retry, échec silencieux (RAM du Cerbo
ménagée ; si le Pi est éteint, rien ne se passe).

## Installation (5 minutes)

1. Ouvrir le Node-RED du Cerbo : `http://<ip-cerbo>:1881` (Venus OS Large).
2. Menu ☰ → **Import** → coller le contenu de `journal-vers-pi.flow.json`
   (dans ce dossier) → Import.
3. Deux nœuds apparaissent : **« copie journal vers le Pi »** (function) et
   **« POST /journal (Pi Haku) »** (http request).
4. Double-cliquer le nœud function et remplacer `PI_HOST = '192.168.8.20'`
   par l'**IP fixe du Pi** (réservation DHCP faite dans le Pepwave).
5. Câbler l'**entrée** du nœud function en **parallèle** de l'envoi Google
   Apps Script : sur la sortie du nœud du flow « Journal auto » qui construit
   l'objet des 15 champs (celui qui alimente déjà le POST Google), tirer un
   fil supplémentaire vers « copie journal vers le Pi ».
6. **Deploy**.

## Vérification

- Côté Pi : `tail -f /var/lib/haku/journal/haku_journal.jsonl` puis, dans le
  Node-RED du Cerbo, réinjecter une fin de navigation de test (ou attendre la
  prochaine vraie arrivée) → une ligne JSON apparaît, et la nav est visible
  sur la carte `http://<ip-pi>:1880/dashboard/navigations`.
- Test à la main sans le Cerbo :
  `curl -X POST http://<ip-pi>:1880/journal -H 'Content-Type: application/json' -d '{"depart_ts":"2026-08-27T09:00:00Z","arrivee_ts":"2026-08-27T12:00:00Z","port_depart":"Test","port_arrivee":"Test2","lat_arrivee":43.27,"lon_arrivee":5.35,"distance_nm":12}'`

## Notes

- **Timeout** : la limite de 3 s est portée par `msg.requestTimeout`
  (honoré par Node-RED depuis la version 1.1 — le Node-RED de Venus OS
  Large est bien plus récent). Le nœud « http request » du cœur n'a PAS de
  propriété de timeout par nœud (vérifié dans les sources Node-RED : seul
  `msg.requestTimeout` ou le réglage global `httpRequestTimeout` de
  settings.js existent). Si votre Venus était un jour rétrogradé sous
  Node-RED 1.1 (improbable), le défaut global de 120 s s'appliquerait —
  sans blocage du flow (envoi asynchrone, sortie non câblée).
- Aucune authentification sur `/journal` : le port 1880 du Pi n'est joignable
  que depuis le LAN du bord et Tailscale (pare-feu nftables du Pi).
- L'échec est **volontairement silencieux** côté Cerbo (`senderr` activé :
  l'erreur repart dans le message, personne ne l'écoute). Le rattrapage d'un
  Pi éteint se fait avec `scripts/import-journal.py` sur l'export CSV du
  Cerbo ou du Google Sheet (voir README du Pi, section Import historique).
- Ne toucher à RIEN d'autre dans le flow « Journal auto » du Cerbo.
