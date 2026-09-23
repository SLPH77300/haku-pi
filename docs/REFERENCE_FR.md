# Haku Pi — Supervision du bord (Amel 50 « Haku »)

> Haku Pi — version 1.2.0 (30/08/2026) — mode headless par défaut

Raspberry Pi 4 embarqué, connecté au **Cerbo GX Victron** par MQTT, qui fournit :

- un **dashboard** (Node-RED Dashboard 2.0) ouvert sur la **page
  « Surveillance »** (v1.2, esprit maquette v5) : eau dans les cales, batterie
  en très gros, vent enregistré 48 h, état de la liaison — puis les pages
  **Bord** (détail complet) et **Navigations** (carte) ; accessible depuis
  téléphone/tablette (LAN du bord + **Tailscale** à travers le CGNAT Starlink) ;
- le **verrou COLREG du feu de mouillage** : feu piloté par le relais 1 du
  Cerbo, allumé automatiquement la nuit **uniquement en mode MOUILLAGE** ;
  en mode **MARINA (défaut)** le feu est verrouillé ÉTEINT ;
- des **alertes email** : SOC bas, tension basse, température batterie, perte
  du quai, absence de pleine charge depuis 14 jours, Cerbo injoignable,
  Pi redémarré — et v1.2 : **vent fort** (`WIND_ALERT_KT`), **dérive SOC à
  quai** (`SURV_SOC_H`), **module Waveshare injoignable** ;
- un **journal CSV quotidien** (min/max SOC/V/T°, Wh solaires) et, v1.2, un
  **historique long InfluxDB + Grafana** (traceur continu, météo, électrique) ;
- v1.2 en option après câblage : **module Waveshare Modbus TCP** (8 relais +
  8 DI — flotteurs de cale et alimentation instruments), **éclairage
  extérieur** sur le relais 2 du Cerbo, **heartbeat dead-man** healthchecks.io ;
- une conception **« bateau inoccupé »** : watchdog matériel, services
  auto-relancés, healthcheck, carte SD protégée, reprise totale sans
  intervention après coupure de courant.

```
Cerbo GX (Venus OS) ──┐                        ┌──► écran HDMI (kiosk Chromium)
  SmartShunt, MPPT,   ├─ LAN du bord ──► Pi 4 ─┤
  relais 1 → feu,     │  (routeur          │   └──► alertes SMTP + journal CSV
  (bientôt Quattro)   │   Pepwave)     Tailscale (tunnel sortant)
                      │                    │
            Pepwave ──┴── WAN1 Starlink ───┴── WAN2 SIM cellulaire (IT)
                          (CGNAT)              (CGNAT)  → failover transparent
```

---

## 1. Matériel requis

| Élément | Détail |
|---|---|
| Raspberry Pi 4 Model B | 2 Go de RAM minimum (4 Go confortable) |
| Carte micro-SD | 16 Go minimum, qualité « endurance » recommandée (Sandisk High Endurance / Samsung PRO Endurance) |
| Alimentation | Convertisseur 24 V → 5 V/3 A (9–36 V, déjà prévu à bord), USB-C |
| Écran | HDMI (câble micro-HDMI côté Pi), alimenté séparément |
| Réseau | Câble Ethernet (RJ45) vers le routeur **Peplink/Pepwave** du bord (à 5 cm), même LAN que le Cerbo |
| Feu de mouillage | Câblé sur le **relais 1** du Cerbo GX (voir §6 — à câbler à bord) |

Aucun clavier/souris nécessaire après installation (SSH + Tailscale).

### 1.1 Réseau du bord — Pepwave, Starlink + SIM cellulaire

Topologie : le Pi et le Cerbo GX sont tous deux sur le **LAN du routeur
Pepwave**, qui agrège **deux WAN** : **Starlink** et une **SIM cellulaire
italienne** (failover/agrégation gérés par le Pepwave).

Conséquences pratiques :

- **Les deux WAN sont en CGNAT** (Starlink ET cellulaire) : aucune redirection
  de port entrante n'est possible, quel que soit le WAN actif. C'est
  précisément ce qui impose **Tailscale** (tunnel sortant, §7) — ne pas
  perdre de temps avec du DynDNS ou de l'ouverture de ports.
- **Réservations DHCP obligatoires** : dans l'interface du Pepwave
  (`Network → LAN → DHCP Reservation`), figer l'IP du **Pi** et celle du
  **Cerbo** (d'après leurs adresses MAC). Le Cerbo garde ainsi une IP stable
  → `CERBO_HOST` fiable (mettre cette IP plutôt que `venus.local`), et le Pi
  est toujours au même endroit sur le LAN.
- **Failover Starlink ↔ SIM transparent pour le Pi** : une bascule WAN change
  éventuellement l'IP publique et la latence, mais tout le trafic du Pi est
  soit local au LAN (MQTT ↔ Cerbo, dashboard, kiosk), soit auto-reconnectant
  (Tailscale et la connexion VRM du Cerbo rétablissent seuls leur tunnel).
  Aucune configuration côté Pi, rien à faire après une bascule.
- **Volume data (SIM italienne)** : le trafic WAN du Pi est faible —
  MQTT reste sur le LAN (0 octet WAN), une alerte email pèse quelques Ko,
  Tailscale au repos ≈ quelques Mo/jour (keepalives). Ordre de grandeur :
  **< 10–15 Mo/jour au repos** ; une consultation du dashboard à distance
  ajoute ~1–3 Mo par session. À côté, le Cerbo (VRM) consomme de l'ordre de
  quelques dizaines de Mo/mois. Les mises à jour apt (plusieurs centaines de
  Mo) sont à lancer manuellement, de préférence quand Starlink est le WAN
  actif.

## 2. Préparer la carte SD (Raspberry Pi Imager)

1. Télécharger **Raspberry Pi Imager** (raspberrypi.com/software).
2. Choisir l'OS (Bookworm, 64-bit) selon le mode d'affichage :
   - **Mode headless (retenu le 29/08/2026)** : **Raspberry Pi OS Lite
     (64-bit)** + `KIOSK_ENABLED=0` dans haku.env. Pas d'écran sur le Pi —
     les instruments sont sur les 4 écrans B&G, la batterie sur le GX Touch,
     le dashboard se consulte sur smartphone/PC (LAN + Tailscale). Plus
     léger (RAM disponible pour InfluxDB/Grafana v1.2), moins d'écritures SD.
   - Avec écran HDMI + kiosk : édition **Desktop** (le kiosk a besoin du
     bureau) et `KIOSK_ENABLED=1`.
3. Ouvrir les réglages (roue dentée / « Modifier les réglages ») :
   - **Nom d'hôte** : `haku`
   - **Utilisateur** : au choix (ex. `bord`) + mot de passe fort ;
   - **SSH : activé, par CLÉ PUBLIQUE uniquement** — coller votre clé
     (`~/.ssh/id_ed25519.pub`). Pas d'authentification par mot de passe ;
   - Wi-Fi : inutile (Ethernet) — laisser vide ;
   - Locale : `Europe/Paris`, clavier `fr`.
4. Écrire la carte, l'insérer, brancher Ethernet + alimentation.

## 3. Installation

**Préalable réseau** : dans le Pepwave, créer les **réservations DHCP** du Pi
et du Cerbo (§1.1) et noter l'IP du Cerbo pour `CERBO_HOST`.

Depuis votre poste (le Pi doit être joignable — `haku.local` ou son IP) :

```bash
# Copier le dépôt sur le Pi (depuis le dossier haku-pi/ du projet)
scp -r haku-pi/ bord@haku.local:~
ssh bord@haku.local
cd ~/haku-pi
sudo ./install.sh
```

Important : lancer `sudo ./install.sh` **depuis le compte du bord** (celui créé
par l'Imager, ex. `bord`), jamais depuis une session root (`sudo -i`/`su`) —
le script détecte l'utilisateur via `sudo` pour installer Node-RED et le kiosk
sous le bon compte.

`install.sh` est **idempotent** : relançable après une coupure, une erreur ou
pour appliquer une modification — et il **n'écrase jamais des flux que vous
avez modifiés** dans l'éditeur Node-RED (il les détecte par empreinte et
prévient ; voir §12). Il :

1. copie le projet dans `/opt/haku` ;
2. crée `/etc/haku/haku.env` (depuis `config/haku.env.example`) ;
3. installe les paquets requis, **Node-RED** (script officiel Raspberry Pi,
   Node.js 22) et la palette **@flowfuse/node-red-dashboard** ;
4. déploie `settings.js` + `flows.json` (import automatique des flux) ;
5. met en place watchdog matériel, healthcheck, sauvegardes, reboot hebdo ;
6. protège la carte SD (journald en RAM, `/var/log` et `/tmp` en tmpfs,
   swap désactivé, `fsck.repair=yes`) ;
7. configure le pare-feu nftables, Tailscale, l'autologin et le kiosk ;
8. (v1.2) installe et configure **InfluxDB 2 + Grafana** (§9 ter — org,
   buckets, token, dashboards, mots de passe générés) et le **heartbeat**
   (`HEALTHCHECK_URL`). Ces étapes tolèrent l'absence d'internet
   (avertissement, relance plus tard) — le cœur du bord s'installe hors ligne.

Puis :

```bash
sudo nano /etc/haku/haku.env      # remplacer tous les CHANGEME_* (voir §4)
sudo systemctl restart nodered
sudo /opt/haku/scripts/gen-adminauth.sh    # mot de passe de l'éditeur
sudo reboot                        # active tmpfs + watchdog + kiosk
```

Dashboard : **http://haku.local:1880/dashboard** (ou `http://<IP>:1880/dashboard`).
Éditeur Node-RED : **http://haku.local:1880/** (identifiants `NR_ADMIN_USER` / mot de passe choisi).

## 4. Configuration : `/etc/haku/haku.env`

Un seul fichier pour tout le bord. Après modification :
`sudo systemctl restart nodered`.

| Variable | Rôle | Défaut |
|---|---|---|
| `CERBO_HOST` | IP du Cerbo — mettre l'IP **réservée dans le Pepwave** (§1.1), plus fiable que `venus.local` | `venus.local` |
| `RELAY_DBUS_INDEX` | Index MQTT du relais du feu (voir §6 !) | `0` |
| `HAKU_LAT` / `HAKU_LON` | Position pour l'éphéméride du feu | Marseille |
| `TZ` | Fuseau horaire | `Europe/Paris` |
| `SUN_NIGHT_ELEV` | Élévation du soleil sous laquelle il fait nuit | `-0.833` |
| `NR_ADMIN_USER` / `NR_ADMIN_HASH` | Éditeur Node-RED (hash via `gen-adminauth.sh`) | — |
| `SMTP_*` | Serveur d'envoi des alertes (§8) | vide = désactivé |
| `TS_AUTHKEY` | Clé d'enrôlement Tailscale (§7) | — |
| `SUBNET_BORD` | Sous-réseau du bord annoncé par le subnet router | `192.168.8.0/24` |
| `TS_ADVERTISE_ROUTES` | `1` = le Pi route le LAN du bord via Tailscale | `1` |
| `ALERT_*`, `FULLCHARGE_*`, `CERBO_TIMEOUT_MIN`, `ALERT_REMIND_H` | Seuils d'alertes | voir fichier |
| `KIOSK_URL` | Page affichée par le kiosk | dashboard Haku |
| `KIOSK_FORCE_HDMI` | `1` = forcer la sortie HDMI écran éteint (§9) | `0` |
| `JOURNAL_DIR` / `JOURNAL_KEEP_DAYS` | Journal CSV | `/var/lib/haku/journal`, 730 j |
| `SIGNALK_URL` (v1.1) | URL WebSocket Signal K du Cerbo (garder l'hôte = `CERBO_HOST`) | `ws://venus.local:3000/…?subscribe=none` |
| `TRACK_START_KN` / `TRACK_START_S` (v1.1) | Seuil SOG (kn) et durée (s) de détection de départ | `1.5` / `120` |
| `TRACK_INTERVAL_S` / `TRACK_STOP_S` (v1.1) | Intervalle entre points (s, min effectif 10) / immobilité de clôture (s) | `60` / `600` |
| `TRACKS_DIR` / `JOURNAL_JSONL` (v1.1) | Dossier GPX+index carte / fichier du journal de bord | `/var/lib/haku/tracks`, `…/haku_journal.jsonl` |
| `DIGITAL_IN_PUISARD` `…_LAZARETTE` `…_BATTERIES` `…_MACHINE` (v1.1) | Instances digitalinput des 4 flotteurs (§9 bis) — vide = non câblé | vides |
| `INSTR_RELAY_INDEX` (v1.1, **obsolescent**) | Index MQTT du relais « instruments » Cerbo — ne sert plus que si `WAVESHARE_ENABLED=0` (§9 ter, changelog) | `1` |
| `GEOFENCE_M` / `GEOFENCE_ALERT_M` (v1.1) | Rayon port déclaré (notification d'arrivée) / seuil d'alerte de dérive en MARINA | `150` / `250` |
| `OPEN_METEO` (v1.1) | `1` = prévisions Open-Meteo 2×/jour | `1` |
| `WIND_ALERT_KT` (v1.2) | Seuil de rafale (kn) de l'alerte « vent fort » du graphe 48 h | `35` |
| `SURV_SOC_H` / `SURV_SOC_DROP` (v1.2) | Durée (h) et amplitude (points) de la dérive SOC à quai avant alerte | `48` / `5` |
| `INFLUX_ENABLED` / `INFLUX_DATA_DIR` (v1.2) | InfluxDB 2 local (§9 ter) / dossier des données (SD, déplaçable SSD) | `1` / `/var/lib/haku/influx` |
| `INFLUX_ORG` `INFLUX_BUCKET` `INFLUX_BUCKET_AGG` (v1.2) | Org + bucket brut 30 j + bucket agrégé 730 j | `haku` / `haku_raw` / `haku_agg` |
| `INFLUX_URL` / `INFLUX_TOKEN` / `INFLUX_ADMIN_PASS` (v1.2) | API locale / **générés et écrits par install.sh** | `http://127.0.0.1:8086` / — |
| `GRAFANA_ENABLED` / `GRAFANA_PORT` / `GRAFANA_ADMIN_PASS` (v1.2) | Grafana (§9 ter) / port / mot de passe admin **généré par install.sh** | `1` / `3001` / — |
| `WAVESHARE_ENABLED` / `WAVESHARE_HOST` / `WAVESHARE_PORT` / `WAVESHARE_UNIT_ID` (v1.2) | Module relais/DI Modbus TCP (fiche de câblage) — `0` tant que non câblé | `0` / vide / `502` / `1` |
| `WAVESHARE_DI_*` / `WAVESHARE_DI_INVERT` / `WAVESHARE_INSTR_RELAY` (v1.2) | Mapping DI des 4 cales / polarité (ohmmètre !) / relais instruments | `1-4` / `0` / `1` |
| `RELAY_LIGHT_INDEX` / `LIGHT_AUTO_OFF_MIN` (v1.2) | Relais Cerbo de l'éclairage extérieur (borne Relay 2 = 1) / minuterie (0 = off) | `1` / `0` |
| `HEALTHCHECK_URL` (v1.2) | URL de heartbeat dead-man (§9 ter) — vide = désactivé | vide |

## 5. Côté Cerbo GX

1. **Activer le broker MQTT local** : Remote Console →
   `Settings → Services → MQTT on LAN (SSL)` **ET** `MQTT on LAN (Plaintext)`
   → **On**. (Le Pi utilise le port 1883 en clair, sur le LAN uniquement.)
2. **Relais en manuel** : `Settings → Relay → Function` (relais 1) →
   **Manual** (« Manuel »). Sans cela, l'écriture MQTT du relais est ignorée.
3. **Portal ID** : `Settings → VRM online portal → VRM Portal ID` — purement
   informatif : le flux le **découvre automatiquement** (topic
   `N/+/system/0/Serial`) et l'affiche dans le groupe « Système » du dashboard.
4. Température batterie : sur le **SmartShunt**, l'entrée Aux doit être
   configurée en **sonde de température** (app VictronConnect → SmartShunt →
   Réglages → Divers → entrée Aux = Température). `TODO-VERIFIER-A-BORD` :
   sans cela le topic `.../Dc/Battery/Temperature` n'existe pas et la tuile
   Température reste vide (les autres alertes fonctionnent normalement).
5. Consommation DC : activer `Settings → System setup → Has DC system` pour
   publier `.../Dc/System/Power`. `TODO-VERIFIER-A-BORD`.

## 6. Feu de mouillage — câblage et vérification du relais

**À CÂBLER À BORD** : le feu de mouillage (tête de mât) doit être alimenté à
travers le contact **NO/COM du relais 1** du Cerbo GX :

```
+24V bord ──── fusible 2 A ──── COM (Relay 1) ── NO (Relay 1) ──── feu de mouillage ──── masse
```

- Relais du Cerbo : contact sec 6 A/30 VDC max — un feu LED (< 1 A) passe
  directement ; sinon intercaler un relais de puissance.
- Laisser l'interrupteur manuel du tableau en parallèle si l'on veut pouvoir
  forcer le feu indépendamment du Pi (recommandé : la redondance prime).

**ATTENTION au décalage de numérotation** (source de 100 % des confusions) :

| Borne physique Cerbo | Topic MQTT |
|---|---|
| « Relay 1 » | `.../system/0/Relay/0/State` |
| « Relay 2 » | `.../system/0/Relay/1/State` |

Le défaut `RELAY_DBUS_INDEX=0` correspond donc à la **borne Relay 1**.

**`TODO-VERIFIER-A-BORD` — procédure (5 min, avec MQTT Explorer)** :

1. Installer **MQTT Explorer** (PC/Mac) → se connecter à `CERBO_HOST:1883` ;
2. observer `N/<portal_id>/system/0/Relay/…/State` ;
3. dans la Remote Console : `Settings → Relay → Manual control` basculer le
   relais **câblé au feu** et noter quel index (`0` ou `1`) change dans
   MQTT Explorer ;
4. reporter cet index dans `RELAY_DBUS_INDEX` puis
   `sudo systemctl restart nodered`.

**Fonctionnement du verrou COLREG** (règle 30 RIPAM : feu blanc 360° du
coucher au lever du soleil au mouillage) :

- toggle **« Mode MOUILLAGE »** sur le dashboard (groupe Feu de mouillage) ;
- mode **persisté** sur SD : survit au reboot et aux coupures de courant ;
- `MARINA` (défaut) : feu **verrouillé éteint**, ré-affirmé toutes les 5 min
  (même si quelqu'un l'a allumé à la main via la console) ;
- `MOUILLAGE` : feu allumé quand l'élévation du soleil < `SUN_NIGHT_ELEV`,
  éteint le jour. Précision de l'éphéméride embarquée : ± 3 minutes.

## 7. Tailscale — accès distant à travers le CGNAT (Starlink et SIM)

Les deux WAN du Pepwave (Starlink **et** cellulaire) sont en CGNAT :
**aucun port entrant possible**, quel que soit le WAN actif. Tailscale établit
un tunnel WireGuard **sortant**, donc fonctionne dans les deux cas (connexion
directe si possible, sinon relais DERP), et survit tout seul aux bascules
Starlink ↔ SIM du Pepwave (le tunnel se rétablit, l'IP Tailscale `100.x.y.z`
ne change jamais).

1. Créer un compte tailscale.com (gratuit jusqu'à 3 utilisateurs/100 machines).
2. Admin console → `Settings → Keys` → **Generate auth key…** — cocher
   `Reusable` et si possible `Pre-approved`. Copier `tskey-auth-…` dans
   `TS_AUTHKEY` (haku.env), puis `sudo ./install.sh` (relance idempotente).
3. **Approuver la route** : Admin console → Machines → `haku` → menu
   `…` → `Edit route settings` → cocher `192.168.8.0/24` (= `SUBNET_BORD`).
   Le Pi joue alors les **subnet router** : depuis le téléphone (app
   Tailscale active), on atteint le **Cerbo** (`http://192.168.8.x`), la
   Remote Console, etc.
4. **MagicDNS** (activé par défaut) : le dashboard devient
   `http://haku:1880/dashboard` depuis n'importe où.
5. Le Pi est enrôlé avec `--accept-dns=false` (il ne laisse pas Tailscale
   toucher au DNS du bord) et `--hostname=haku`.

Notes : la clé d'enrôlement peut être révoquée après usage ; penser à
**désactiver l'expiration de clé** de la machine `haku` dans la console
(Machines → `…` → `Disable key expiry`) pour un bateau inoccupé.

## 8. Alertes email (SMTP)

Renseigner dans `haku.env` :

```
SMTP_HOST=smtp.exemple.fr   SMTP_PORT=587   SMTP_SECURITY=starttls
SMTP_USER=…                 SMTP_PASS=…
SMTP_FROM=haku-pi@exemple.fr
SMTP_TO=vous@exemple.fr[,second@exemple.fr]
```

- Gmail : `smtp.gmail.com:587`, `starttls`, **mot de passe d'application**
  (compte Google → Sécurité → validation en 2 étapes → mots de passe des
  applications).
- OVH : `ssl0.ovh.net:465`, `ssl`.
- Test : bouton **« Tester l'alerte email »** du dashboard (groupe Système),
  puis vérifier la réception et `journalctl -t haku-alert`.

Toutes les alertes sont AUSSI : affichées en notification sur le dashboard,
listées dans « Alertes actives », tracées dans `/var/lib/haku/alerts.log`.
Une alerte qui persiste est rappelée toutes les `ALERT_REMIND_H` heures
(défaut 24 h) ; le retour du quai/du Cerbo envoie un message de rétablissement.

**Secours sans SMTP** : laisser `SMTP_HOST` vide et configurer les **alarmes
VRM** (vrm.victronenergy.com → installation Haku → Settings → Alarm rules :
SOC bas, tension, perte grid — email/push par les serveurs Victron via la
connexion VRM du Cerbo). Les deux systèmes sont complémentaires et
indépendants : VRM alerte même si le Pi est mort.

## 9. Écran & kiosk

> **Mode headless (`KIOSK_ENABLED=0`, image Lite) : cette section ne
> s'applique pas** — aucun kiosk, aucun autologin, dashboard sur
> smartphone/PC uniquement.

- Au boot : autologin bureau → labwc (ou wayfire) lance l'unité utilisateur
  `haku-kiosk.service` → `kiosk.sh` attend que le dashboard réponde puis
  ouvre **Chromium plein écran** (supervisé : re-lancé s'il plante).
- Veille écran désactivée (`raspi-config do_blanking`).
- **Curseur** : sous Wayland, aucun curseur ne s'affiche si **aucune souris
  n'est branchée** (cas normal à bord). Si un curseur gêne :
  débrancher la souris, ou `TODO-VERIFIER-A-BORD` selon la version de labwc
  (pas de méthode officielle de masquage à ce jour).
- **Écran éteint au boot** : si l'écran HDMI est mis sous tension après le
  Pi et reste noir, mettre `KIOSK_FORCE_HDMI=1` (haku.env) puis
  `sudo ./install.sh` : ajoute `video=HDMI-A-1:1920x1080M@60D` à
  `cmdline.txt` (syntaxe KMS standard — `TODO-VERIFIER-A-BORD` avec votre
  écran ; adapter `KIOSK_HDMI_MODE` à sa résolution native).
- Éteindre l'affichage à distance (le dashboard reste servi) :
  `sudo -u bord XDG_RUNTIME_DIR=/run/user/$(id -u bord) systemctl --user stop haku-kiosk`
  (remplacer `bord` par votre utilisateur ; `start` pour le relancer).
- Note : si l'installation passe par `wayfire.ini` (premières images
  Bookworm), la mise à jour de ce fichier préserve les réglages mais pas ses
  éventuels commentaires.

## 9 bis. Nouveautés v1.1 — Signal K, carte, traces, flotteurs, commandes

### Instruments · météo du bord (Signal K)

Le Cerbo tourne en **Venus OS Large** : son serveur **Signal K** (port 3000)
publie déjà vent, vitesses, position, sonde… Le Pi s'y abonne en WebSocket
(`SIGNALK_URL`, une seule connexion partagée par tout le système — le Cerbo
et son 1 Go de RAM sont ménagés : abonnement sélectif, aucun poll REST).
La carte « Instruments » du dashboard affiche : vent vrai (+ direction),
**rafales** (max 10 min), vent apparent, **baromètre + tendance 3 h**, sonde,
SOG, cap, T° eau/air — chaque donnée que le bord ne publie pas affiche « — ».
`TODO-VERIFIER-A-BORD` : les chemins Signal K effectivement publiés dépendent
des instruments NMEA2000 raccordés (vérifier sur `http://<cerbo>:3000` →
Data Browser).

**Prévisions Open-Meteo** (`OPEN_METEO=1`, sans clé API) : 2 requêtes à 07 h
et 19 h → ligne « Demain : vent X kn (raf. Y) NW · houle Z m » sous les
instruments. Trafic : ~4 requêtes HTTP légères par jour.

### Traces GPS + carte « Navigations »

- Détection automatique : SOG > `TRACK_START_KN` (1,5 kn) pendant
  `TRACK_START_S` (2 min) → **trace ouverte**, un point toutes les
  `TRACK_INTERVAL_S` (60 s ; minimum effectif 10 s = cadence du moteur) ;
  immobilité de `TRACK_STOP_S` (10 min) → **fichier GPX clos** dans
  `/var/lib/haku/tracks/` + reconstruction de l'index de la carte.
  Volume : **3-5 Ko par heure de navigation** (une transat ≈ 2 Mo).
  La trace en cours survit au reboot (contexte persisté).
- Page **« Navigations »** du dashboard (`/dashboard/navigations`) : carte du
  monde interactive (design sombre v4) — **Leaflet servi en local**
  (`/static/leaflet/`, embarqué dans le dépôt, AUCUN CDN), fond OSM +
  surcouche **OpenSeaMap**, traces colorées par saison
  (#3987e5/#d95926/#199e70), clic sur un trajet → **fiche complète** de la
  nav (champs du journal), filtres par année, stats du carnet (NM total,
  nb navs), **position actuelle** rafraîchie toutes les 10 s.
- **Limite hors-ligne assumée** : les *tuiles* de fond de carte viennent
  d'internet (OSM/OpenSeaMap, avec cache navigateur) ; sans internet la carte
  affiche un fond sombre + un bandeau explicatif, **les traces et fiches
  restent affichées** (données 100 % locales).

### Journal de bord (Cerbo → Pi)

Le flow « Journal de bord auto » du **Cerbo** reste le maître (Google Sheet +
CSV locaux inchangés). Le Pi en reçoit une **copie** par `POST /journal`
(LAN/Tailscale uniquement — pare-feu existant) : appliquer le patch **2 nœuds**
sur le Cerbo → voir `cerbo/PATCH_Journal_vers_Pi.md` (import direct de
`cerbo/journal-vers-pi.flow.json`, fire-and-forget, échec silencieux).
Chaque nav reçue est archivée dans `haku_journal.jsonl` et liée à sa trace
GPX (départ à ± 3 h) → popup complète sur la carte.

**Import de l'historique** (Caraïbes, Açores…) :

```bash
# export CSV du Google Sheet ou du /data/haku_journal.csv du Cerbo
python3 /opt/haku/scripts/import-journal.py export.csv           # ou --dry-run
```

Colonnes FR reconnues automatiquement, positions en **degrés décimaux ou
degrés-minutes** (`43°16.5'N 5°21.2'E`), dédoublonnage par date de départ,
reconstruction de l'index carte incluse. XLSX accepté si `openpyxl` présent
(sinon exporter en CSV).

### Flotteurs d'envahissement (4 entrées digitales du Cerbo)

Après câblage des 4 flotteurs (fiche à bord), renseigner les **instances**
dans `haku.env` (`DIGITAL_IN_PUISARD`, `…_LAZARETTE`, `…_BATTERIES`,
`…_MACHINE`) — visibles dans MQTT Explorer sous
`N/<id>/digitalinput/<instance>/State`. Vide = zone non câblée (le groupe
« Envahissement » est masqué si aucune zone n'est configurée).
Anti-rebond 3 s ; **8 = OK, 9 = Alarme** (`TODO-VERIFIER-A-BORD` après
câblage) ; alarme → email + notification + tuile horodatée ; le **nombre
d'événements par zone** est ajouté chaque jour au journal CSV (colonnes
`puisard;lazarette;batteries;machine` — utile pour l'enquête lazarette).

### Commandes (design v4)

- **Mode MOUILLAGE/MARINA + feu** : inchangés (v1.0.1).
- **Alimentation instruments** : bouton à **appui long 2 s** (relâcher avant
  2 s = rien + rappel) → bascule le **relais 2** du Cerbo
  (`INSTR_RELAY_INDEX=1` = borne « Relay 2 », même décalage borne/index que le
  feu — §6) ; l'état affiché est le retour MQTT réel du relais.
- **« Déclarer ce port »** : enregistre la position actuelle dans
  `/var/lib/haku/ports.json` (nom saisi dans le champ voisin, sinon nom
  automatique ; écriture atomique). **Géofence — PRIMAUTÉ COLREG (règle
  30)** : le système n'éteint **JAMAIS** le feu de mouillage
  automatiquement. À l'entrée dans le rayon `GEOFENCE_M` (150 m) d'un port
  déclaré : si le mode MOUILLAGE a été posé manuellement, il **reste actif**
  (le feu continue de s'allumer la nuit) et une notification rappelle de
  passer en MARINA à la main si l'on est au ponton ; si le mode est déjà
  MARINA, rien ne change. En MARINA près d'un port déclaré, un écart
  > `GEOFENCE_ALERT_M` (250 m) déclenche l'alerte **« position anormale »**
  (amarres/dérive).

### Design v4 appliqué — écarts maquette ↔ Dashboard 2.0

Thème sombre (#1a1a19 / #232321, accent #3987e5), ordre des cartes de la
maquette (Batterie, Instruments, Quai, Solaire, Commandes, Envahissement,
Surveillance·Système, Historique), gros chiffres sur les valeurs clés.
Écarts assumés (capacités D2) : les tuiles restent des widgets D2 standard
(pas de tuile « héros » pleine largeur figée) ; l'appui long est implémenté
via les événements pointerdown/up du bouton D2 (pas d'animation de
progression) ; une zone flotteur non câblée affiche « non câblé » si au
moins une autre l'est (le masquage individuel n'existe pas en D2 — seul le
groupe entier est masqué quand AUCUNE zone n'est configurée).

## 9 ter. Nouveautés v1.2 — Surveillance, Influx/Grafana, Waveshare, heartbeat

### Page « Surveillance » (page par défaut du dashboard)

`http://haku:1880/dashboard` ouvre désormais la page **Surveillance**
(ordre : Surveillance, Bord, Navigations — la page v1.1 « Haku » devient
« Bord », même chemin `/dashboard/haku`, mêmes tuiles). Fidèle à la maquette
v5 (thème sombre #1a1a19/#232321, accent #3987e5), minimaliste — les 4 cartes
qui comptent quand le bateau est seul :

1. **Eau dans les cales** — 4 zones (puisard, lazarette, batteries, salle
   machine) : `SEC` vert / `ALARME EAU` rouge clignotant + horodatage, ligne
   « dernier événement ». Mêmes capteurs et même anti-rebond que la page Bord
   (source Cerbo ou Waveshare selon `WAVESHARE_ENABLED`).
2. **Batterie** — tension en très gros, SOC + courant, et le toggle
   **« Surveillance à quai »** (persisté sur SD comme le mode MOUILLAGE) :
   actif, il échantillonne le SOC **toutes les heures** ; une baisse **continue
   sans remontée** (aucune recharge > 1 point) sur `SURV_SOC_H` h (48) d'au
   moins `SURV_SOC_DROP` points (5) → email **« Le bateau perd de la charge à
   quai »** + notification (chargeur HS, disjoncteur de borne sauté…), message
   de rétablissement quand le SOC remonte.
3. **Vent enregistré** — vent actuel + rafales en gros, **mini-graphe 48 h**
   (moyenne, rafales, ligne de seuil) alimenté par un échantillon toutes les
   10 min depuis la connexion Signal K existante (aucune connexion en plus).
   Ring buffer 48 h **persisté** dans `/var/lib/haku/meteo48h.json` (« 1
   écriture / 10 min », écriture atomique tmp+mv — protection SD), rechargé au
   boot. Le baromètre est stocké dans le même échantillon. Rafales ≥
   `WIND_ALERT_KT` (35) → **email « VENT FORT »** (hystérésis −5 kn, rappel
   `ALERT_REMIND_H`, message de rétablissement).
4. **État liaison** — quai AC, MQTT Cerbo, âge de la dernière donnée, alertes
   actives. Le silence aussi est une alarme : voir le heartbeat plus bas.

### InfluxDB 2 + Grafana « mode SD light » (`INFLUX_ENABLED=1`, `GRAFANA_ENABLED=1`)

`install.sh` (étapes 14-15, idempotentes, dépôts officiels arm64, **pas de
Docker**) installe et configure automatiquement :

- **InfluxDB 2** lié à `127.0.0.1:8086` (invisible du LAN), org/bucket/token
  créés par `influx setup --force` au premier passage — **le token et le mot
  de passe admin sont générés à bord et écrits dans `/etc/haku/haku.env`**,
  jamais dans le dépôt. Données dans `INFLUX_DATA_DIR`
  (`/var/lib/haku/influx`, carte SD pour l'instant ; le jour du SSD USB :
  `systemctl stop influxdb`, `rsync -a` du dossier, changer la variable,
  relancer `install.sh` — rien d'autre). Réglages « SD light » : bucket brut
  `haku_raw` **rétention 30 j** + tâche de downsampling horaire (fenêtres
  10 min, `max` pour les rafales, `mean` pour le reste) vers `haku_agg`
  **730 j**. `MemoryHigh=700M` (drop-in systemd) protège Node-RED.
- **Node-RED → Influx sans palette tierce** (doctrine du projet) : un nœud
  function construit le **line protocol** à la main et POste **par lots
  toutes les 60 s** sur l'API locale `/api/v2/write` (nœud http request
  natif). Séries (1 point/min) : `nav` (lat/lon **en continu** — nav,
  mouillage, port : c'est le traceur —, SOG, cap), `meteo` (vent, rafales,
  baro, sonde, T° air/eau), `elec` (SOC, V, I, P, T° batterie, solaire W,
  conso DC W). Échec d'écriture **silencieux** avec retry borné : le tampon ne
  garde jamais plus de 15 min (état visible dans `/health` → `influx`).
- **Grafana** sur le port **3001** (1880 est pris) : datasource Influx
  provisionnée par fichier (token injecté depuis haku.env à l'installation),
  **3 dashboards** livrés dans le dépôt (`grafana/dashboards/`) :
  - **Traceur** — panneau geomap (couche route) : la position sur la plage de
    temps choisie — le **sélecteur de durée natif** Grafana fait le travail
    (24 h, 7 j, 30 j… et jusqu'à 2 ans via la variable `bucket` → `haku_agg`).
    Fond de carte = internet requis (même limite documentée que la carte
    Leaflet) ;
  - **Météo bord** — vent moyen + rafales, baromètre ;
  - **Électrique** — SOC, tension, courant, solaire + conso DC.
  Admin `admin` / mot de passe **généré par install.sh**
  (`GRAFANA_ADMIN_PASS` dans haku.env ; à changer :
  `sudo /opt/haku/scripts/gen-grafana-pass.sh` — patron de gen-adminauth.sh).
  Anonyme désactivé. **nftables n'ouvre 3001 que depuis `SUBNET_BORD` et
  `tailscale0`** — rien côté internet. `MemoryHigh=300M`.
- RAM totale mesurable à prévoir : Node-RED ~200 Mo + influxd ~200-400 Mo +
  Grafana ~150-250 Mo — confortable sur le Pi 4 Go, et les `MemoryHigh`
  garantissent que Node-RED (la supervision) reste prioritaire.

### Module Waveshare Modbus POE ETH Relay (B) (`WAVESHARE_ENABLED=0` par défaut)

Après câblage (**suivre `FICHE_CABLAGE_Waveshare_Haku.md`** : alimentation par
l'ancienne ligne Starlink 24 V, Ethernet → Pepwave, piquage des 4 DI sur les
boucles d'alarme du folio 11, relais 1 → circuit instruments) et passage à
`WAVESHARE_ENABLED=1` + `WAVESHARE_HOST` :

- le Pi parle **Modbus TCP (port 502) sans palette tierce** : client minimal
  dans des nœuds function au-dessus du nœud **tcp request natif** (en-tête
  MBAP construit à la main, transaction ID vérifié, timeout 1,5 s,
  reconnexion). **FC02** poll des DI toutes les 2 s, **FC01** état **réel**
  des relais toutes les 10 s, **FC05** écritures ;
- les **4 flotteurs de cale** basculent de source : DI du Waveshare (mapping
  `WAVESHARE_DI_*`, polarité `WAVESHARE_DI_INVERT` — contacts NF piqués sur
  les boucles 24 V existantes, **à déterminer à l'ohmmètre**) au lieu des
  entrées Cerbo. Anti-rebond 3 s, alertes email et compteurs du journal CSV
  strictement inchangés ; repli immédiat possible (`WAVESHARE_ENABLED=0`) ;
- le bouton **Instruments (appui long 2 s)** pilote le **relais 1 du module**
  (`WAVESHARE_INSTR_RELAY`) ; l'état affiché est la **lecture FC01 réelle**.
  À chaque démarrage de flux et à chaque reconnexion, l'état **voulu** de
  TOUS les relais est ré-affirmé (défaut : **instruments ON** — circuit de
  navigation —, autres OFF ; états voulus persistés sur SD) ;
- **module muet > 5 min** → email + tuile « Module Waveshare » (groupe
  Système), même patron que « Cerbo injoignable » (rappel, rétablissement).

**Éclairage extérieur (spreader lights)** — nouveau toggle sur la page Bord
(groupe Commandes) : pilote le **relais 2 du CERBO** (topic `Relay/1/State`,
borne « Relay 2 », `RELAY_LIGHT_INDEX=1`), état voulu ré-affirmé toutes les
5 min (patron du feu de mouillage), minuterie optionnelle
`LIGHT_AUTO_OFF_MIN` (0 = désactivée). Actif seulement quand
`WAVESHARE_ENABLED=1` (avant, cette borne alimente les instruments — l'ancien
usage disparaît, voir changelog). Garde-fou : toute commande est refusée si
`RELAY_LIGHT_INDEX` pointait sur le relais du feu (`RELAY_DBUS_INDEX`) — le
**verrou COLREG reste seul maître du feu**.

### Heartbeat dead-man (`HEALTHCHECK_URL`, vide = désactivé)

La logique est inversée par rapport aux alertes email : **c'est le silence qui
alerte**. Un timer systemd (`haku-heartbeat.timer`, 10 min) lance
`curl --max-time 20 "$HEALTHCHECK_URL"` **uniquement si `/health` répond en
local** — Node-RED mort, Pi éteint, WAN coupé ⇒ pas de ping ⇒ le service
externe envoie l'alerte (email/push) même si tout le bord est hors ligne, ce
que les alertes SMTP du Pi ne peuvent pas faire.

Recommandé : **healthchecks.io** (gratuit jusqu'à 20 checks) — créer un check
« Haku Pi », period 10 min, grace 15 min, copier l'URL `https://hc-ping.com/…`
dans `HEALTHCHECK_URL`. Data : un GET de quelques centaines d'octets toutes
les 10 min, ~négligeable même sur la SIM (< 0,15 Mo/jour).

## 10. Journal CSV

- Une ligne par jour à 23:55 dans `/var/lib/haku/journal/haku-AAAA-MM.csv` :
  `date;soc_min;soc_max;v_min;v_max;t_min;t_max;pv_wh;puisard;lazarette;batteries;machine`
  (séparateur `;`, ouvrable dans Excel/LibreOffice ; les 4 dernières colonnes,
  ajoutées en v1.1, comptent les événements de flotteurs du jour).
- Énergie solaire : intégration des puissances MPPT (trapèzes), remise à zéro
  à minuit. Rotation automatique (> `JOURNAL_KEEP_DAYS`).
- Copié chaque nuit dans la sauvegarde `/boot/firmware/haku-backup/`.

## 11. Recette à bord (checklist)

Après installation complète, dérouler dans l'ordre :

1. **Dashboard visible** : `http://haku.local:1880/dashboard` depuis un
   téléphone sur le Wi-Fi du bord → SOC/tension vivants (« Dernière donnée :
   il y a Ns »).
2. **Kiosk** : reboot → l'écran du carré affiche le dashboard plein écran
   sans intervention (< 2 min).
3. **Données Victron** : couper un consommateur → le courant batterie bouge
   dans les 5 s. Portal ID affiché dans « Système ».
4. **Toggle MOUILLAGE** : activer sur le dashboard → notification ; en pleine
   nuit le feu s'allume (ou forcer `SUN_NIGHT_ELEV=90` temporairement pour
   simuler la nuit, puis remettre !). Le relais claque dans le Cerbo.
5. **Verrou MARINA** : repasser MARINA → le feu s'éteint et l'état affiche
   « VERROUILLÉ ÉTEINT ». Allumer le relais à la main dans la Remote
   Console → il est rééteint en ≤ 5 min.
6. **Persistance** : laisser MOUILLAGE, `sudo reboot` → au retour le toggle
   est toujours MOUILLAGE.
7. **Perte du quai simulée** : couper le disjoncteur de quai → après 5 min,
   email « PERTE DU QUAI » + notification (nécessite le Quattro installé ;
   sans lui, l'alerte est simplement inerte).
8. **Cerbo injoignable** : débrancher l'Ethernet du Cerbo 16 min → alerte ;
   rebrancher → message de rétablissement + données de retour seules.
9. **Alerte test** : bouton « Tester l'alerte email » → email reçu.
10. **Coupure sèche** : couper l'alimentation du Pi 30 s puis rétablir →
    tout revient seul (dashboard, kiosk, Tailscale, MQTT) + email
    « Pi redémarré ».
11. **Tailscale** : téléphone en 4G/5G (Wi-Fi coupé) →
    `http://haku:1880/dashboard` et `http://<IP-cerbo>` (Remote Console).
12. **Sauvegarde** : vérifier `/boot/firmware/haku-backup/haku-*.tar.gz`
    après 04:10, ou `sudo /opt/haku/scripts/backup-flows.sh`.
13. **(v1.1) Instruments** : `/dashboard/haku` → vent/SOG/sonde vivants dès
    que le Cerbo publie (Data Browser Signal K en cas de tuile « — »).
14. **(v1.1) Trace** : courte sortie (> 2 min à plus de 1,5 kn) → tuile
    « Trace GPS : NAV » ; 10 min après l'arrêt, un GPX apparaît dans
    `/var/lib/haku/tracks/` et la nav sur `/dashboard/navigations`.
15. **(v1.1) Journal** : patch Cerbo appliqué → à la prochaine arrivée (ou au
    `curl` de test du patch), la fiche s'affiche au clic sur la trace.
16. **(v1.1) Flotteurs** : lever un flotteur à la main → tuile ALARME + email
    en ~5 s ; recâbler → « retour à la normale ».
17. **(v1.1) Appui long** : appui bref sur « Instruments » = message de
    rappel ; appui 2 s = le relais 2 claque, l'état bascule.
18. **(v1.1) Port + géofence** : « Déclarer ce port » au ponton → sortir puis
    revenir en mode MOUILLAGE : à l'entrée du rayon de 150 m le mode **reste
    MOUILLAGE** (le feu s'allumera la nuit — primauté COLREG) et une
    notification rappelle de passer en MARINA à la main ; vérifier ensuite
    l'alerte « position anormale » en s'éloignant > 250 m en MARINA.
19. **(v1.2) Page Surveillance** : `http://haku:1880/dashboard` ouvre la page
    Surveillance (cales, batterie en gros, vent 48 h, liaison) ; les onglets
    Bord et Navigations sont dans le menu.
20. **(v1.2) Vent 48 h** : après 20-30 min, le graphe montre les premiers
    points (2-3 échantillons) ; `cat /var/lib/haku/meteo48h.json` n'est plus
    vide ; reboot → le graphe repart avec son historique.
21. **(v1.2) Surveillance à quai** : activer le toggle → notification ;
    `curl http://127.0.0.1:1880/health` montre `surv_quai: true` ; reboot →
    toggle toujours actif. (Le test complet de la dérive demande 48 h — ou
    baisser temporairement `SURV_SOC_H=2` pour valider, puis remettre !)
22. **(v1.2) InfluxDB** : `curl http://127.0.0.1:8086/health` → `"pass"` ;
    après 2-3 min, `/health` du Pi montre `influx: {buffered: 0-3, errors: 0}`
    (0 buffered = écritures OK).
23. **(v1.2) Grafana** : `http://haku.local:3001` depuis le téléphone du bord
    → login admin (mot de passe `GRAFANA_ADMIN_PASS` de haku.env) → dossier
    Haku → « Traceur » affiche la position, « Électrique » le SOC. Vérifier
    que 3001 ne répond PAS depuis un réseau extérieur sans Tailscale.
24. **(v1.2) Heartbeat** : renseigner `HEALTHCHECK_URL`, attendre 10 min → le
    check healthchecks.io passe « up » ; couper Node-RED
    (`sudo systemctl stop nodered`) 20 min → alerte « down » du service
    externe ; relancer → « up ».
25. **(v1.2) Waveshare** : après câblage, dérouler la recette de
    `FICHE_CABLAGE_Waveshare_Haku.md` (§7 : 12 points — flotteurs, relais
    instruments, panne de module, éclairage extérieur).

## 12. Fiabilité — ce qui tourne tout seul

| Mécanisme | Détail | Commande de contrôle |
|---|---|---|
| Watchdog **matériel** | gel noyau/systemd → reboot auto (15 s) | `journalctl -b \| grep -i watchdog` |
| `Restart=always` | nodered, kiosk relancés à tout crash | `systemctl status nodered` |
| Healthcheck | `/health` sondé toutes les 2 min ; 3 échecs → restart nodered ; 5 cycles KO → reboot (max 1/j) | `journalctl -t haku-healthcheck` |
| Reconnexion MQTT/Tailscale | retries infinis intégrés | dashboard « MQTT Cerbo » |
| Reboot hebdo | dimanche 04:30, précédé d'une sauvegarde ; **désactivable** : `sudo systemctl disable --now haku-reboot.timer` | `systemctl list-timers` |
| Sauvegarde quotidienne | 04:10 → `/boot/firmware/haku-backup/` (7 archives ; le dimanche une 2e sauvegarde a lieu à 04:30 juste avant le reboot — normal) | `ls /boot/firmware/haku-backup` |
| Protection SD | journald en RAM, `/var/log` + `/tmp` en tmpfs, swap off, cache Chromium en RAM, contexte flushé ≤ 1 écriture/30 s, météo 48 h ≤ 1 écriture/10 min | `df -h /var/log` |
| fsck auto | `fsck.repair=yes` (cmdline) | `cat /boot/firmware/cmdline.txt` |
| (v1.2) RAM bornée Influx/Grafana | `MemoryHigh=700M` (influxdb) et `300M` (grafana) via drop-ins : Node-RED garde la priorité | `systemctl show influxdb -p MemoryHigh` |
| (v1.2) Heartbeat dead-man | timer 10 min → `HEALTHCHECK_URL` si `/health` OK ; le silence alerte via le service externe | `journalctl -t haku-heartbeat` |

**Débogage** : les logs étant en RAM, pour investiguer un problème récurrent :
`sudo rm /etc/systemd/journald.conf.d/10-haku-volatile.conf && sudo systemctl
restart systemd-journald` (logs persistants), investiguer, puis relancer
`sudo ./install.sh` pour remettre le mode volatile.

**Mise à jour** : `sudo /opt/haku/scripts/update.sh` (recopie + redéploiement),
`--palette` pour mettre à jour Dashboard 2.0. Si vous avez **modifié les flux
dans l'éditeur**, la ré-exécution d'install.sh/update.sh les **préserve**
(détection par empreinte sha256 dans `/etc/haku/flows.deployed.sha256`) et
affiche un avertissement ; pour revenir à la version du dépôt : supprimer
`~/.node-red/flows.json` puis relancer (l'ancien reste en
`flows.json.avant-haku.*` et dans les sauvegardes). Node-RED lui-même : relancer le
script officiel (`bash <(curl -sL https://github.com/node-red/linux-installers/releases/latest/download/install-update-nodered-deb)`).

## 13. Sécurité

- **Pare-feu nftables** : tout est fermé sauf SSH (22), Node-RED (1880) et
  Grafana (3001, v1.2) depuis `SUBNET_BORD` et `tailscale0` ; mDNS/DHCP/ICMP
  autorisés ; UDP 41641 ouvert pour les connexions directes WireGuard. Rien
  n'est exposé côté Internet (Starlink CGNAT ne le permettrait de toute façon
  pas). **InfluxDB (8086) n'est PAS dans le pare-feu : il écoute uniquement
  sur 127.0.0.1** (drop-in systemd) — seuls Node-RED et Grafana, locaux, y
  accèdent ; l'interface web Influx s'atteint au besoin par tunnel SSH
  (`ssh -L 8086:127.0.0.1:8086 bord@haku`).
- **Éditeur Node-RED** : `adminAuth` obligatoire (hash bcrypt). Le
  **dashboard** reste volontairement sans authentification : il n'est
  joignable que du LAN du bord et de votre tailnet (choix documenté ; pour
  le protéger aussi, voir `httpNodeAuth` dans la doc Node-RED).
- **SSH par clé uniquement** — si l'installation ne l'a pas déjà fait via
  l'Imager :
  ```bash
  # depuis votre poste : copier la clé
  ssh-copy-id bord@haku.local
  # sur le Pi : désactiver le mot de passe
  sudo nano /etc/ssh/sshd_config.d/haku.conf
      PasswordAuthentication no
      KbdInteractiveAuthentication no
  sudo systemctl restart ssh
  # tester une NOUVELLE session AVANT de fermer l'actuelle !
  ```
- **Secrets** : uniquement dans `/etc/haku/haku.env` (droits 640
  root:utilisateur). La sauvegarde `/boot/firmware/haku-backup` inclut ce
  fichier par défaut (pratique pour reconstruire vite) : quiconque possède
  physiquement la carte SD a de toute façon le système entier. Pour l'exclure :
  `BACKUP_INCLUDE_ENV=0` dans haku.env.
- La clé `TS_AUTHKEY` peut être révoquée dans la console Tailscale après
  enrôlement.

## 14. Dépannage

| Symptôme | Piste |
|---|---|
| Dashboard vide, « aucune donnée reçue » | MQTT on LAN activé sur le Cerbo ? `CERBO_HOST` joignable ? (`ping`, puis MQTT Explorer → topics `N/...`) |
| Tuile Température vide | Aux du SmartShunt pas en mode température (§5.4) |
| « Quai / AC » vide | Normal sans Quattro (aucun topic vebus) |
| Le relais ne claque pas | Fonction du relais ≠ Manual dans le Cerbo, ou mauvais `RELAY_DBUS_INDEX` (§6) |
| Kiosk écran noir | `KIOSK_FORCE_HDMI=1` ; état du service : `sudo -u bord XDG_RUNTIME_DIR=/run/user/$(id -u bord) systemctl --user status haku-kiosk` |
| Éditeur : mot de passe refusé | Relancer `gen-adminauth.sh` puis `systemctl restart nodered` |
| Pas d'email | `journalctl -t haku-alert` ; tester le bouton dashboard ; vérifier port/SECURITY |
| Tailscale offline | `tailscale status` ; route approuvée ? clé expirée ? (console admin) |
| Node-RED KO | `journalctl -u nodered -e` ; le healthcheck le relance sous 2-6 min |
| Tout inspecter | `curl http://127.0.0.1:1880/health` (JSON complet) |

## 15. Consommation électrique

| Poste | Puissance | Ah/j @ 24 V |
|---|---|---|
| Pi 4 headless (Node-RED + MQTT, sans kiosk ni écran) | ≈ 2,5–3,2 W | 2,5–3,2 |
| Pi 4 avec kiosk (Chromium + écran HDMI actif) | ≈ 3,2–4,0 W | 3,2–4,0 |
| Pertes convertisseur 24→5 V (~90 %) | ≈ 0,4 W | 0,4 |
| **Total Pi seul** | **≈ 3,6–4,4 W** | **≈ 3,6–4,4 Ah/j** |

Dans la cible 3–6 Ah/j. L'écran du carré est le poste dominant s'il reste
allumé 24 h/24 (10–25 W selon modèle) : l'éteindre quand le bord est inoccupé
(le Pi et le dashboard restent accessibles à distance). Sur un parc de
920 Ah, le Pi seul représente ~0,45 %/jour.

**Budget data (si la SIM du Pepwave est le WAN actif)** : trafic WAN du Pi
< 10–15 Mo/jour au repos (Tailscale idle + emails) ; consultation du dashboard
à distance ≈ 1–3 Mo/session ; mises à jour apt à réserver aux périodes
Starlink. Détail en §1.1.

## 16. Récapitulatif des `TODO-VERIFIER-A-BORD`

| # | Point | Où | Procédure |
|---|---|---|---|
| 1 | Index MQTT du relais du feu (`RELAY_DBUS_INDEX`) | §6 | MQTT Explorer + Manual control |
| 2 | Topic température batterie (Aux SmartShunt) | §5.4 | VictronConnect + MQTT Explorer (`Dc/Battery/Temperature`) |
| 3 | `Has DC system` pour la conso DC | §5.5 | Remote Console + tuile « Conso DC » |
| 4 | Entrée AC : topics présents seulement avec le Quattro | §14 | à revalider à l'installation du Quattro (recette §11.7) |
| 5 | `video=HDMI-A-1:…` si écran éteint au boot | §9 | tester avec l'écran du carré |
| 6 | Curseur kiosk si souris branchée | §9 | débrancher la souris |
| 7 | Précision éphéméride sur zone de navigation | §6 | comparer 2-3 soirs avec les éphémérides du Bloc Marine |
| 8 | (v1.1) Instances des 4 flotteurs + valeurs 8/9 | §9 bis | après câblage : MQTT Explorer sur `N/<id>/digitalinput/+/State`, lever chaque flotteur, noter l'instance → `DIGITAL_IN_*` |
| 9 | (v1.1) `INSTR_RELAY_INDEX` ↔ borne « Relay 2 » | §9 bis | même procédure que le feu (§6), fonction du relais sur Manual |
| 10 | (v1.1) Chemins Signal K publiés par le bord | §9 bis | `http://<cerbo>:3000` → Data Browser (vent vrai vs apparent, T° eau/air, pression) |
| 11 | (v1.1) Tuiles carte = internet requis | §9 bis | vérifier le bandeau hors-ligne + l'affichage des traces sans internet |
| 12 | (v1.2) Adresses Modbus réelles du Waveshare (FC01/02/05, unit ID) | fiche câblage §2 | au banc avant la pose — voir TODO-BANC.md |
| 13 | (v1.2) Polarité des 4 boucles d'alarme (`WAVESHARE_DI_INVERT`) | fiche câblage §3 | ohmmètre/voltmètre boucle par boucle, flotteur levé/reposé |
| 14 | (v1.2) Rendu du graphe vent 48 h + couleurs des tuiles Surveillance | §9 ter | contrôle visuel sur téléphone après 30 min de données |
| 15 | (v1.2) Panneau geomap Grafana (couche route) sur les données réelles | §9 ter | après 1 h de traceur, plage 1 h puis 24 h |

## 17. Changelog

### v1.2.0 (30/08/2026)

- **Page « Surveillance » par défaut** (esprit maquette v5) : eau dans les
  cales (4 zones vert/rouge + horodatage), batterie (tension en très gros,
  SOC, courant), toggle **Surveillance à quai** + alarme **dérive SOC**
  (`SURV_SOC_H`/`SURV_SOC_DROP`), **vent enregistré 48 h** (graphe moyenne +
  rafales, ring buffer persisté `/var/lib/haku/meteo48h.json`, 1 écriture/
  10 min) + alerte **vent fort** (`WIND_ALERT_KT`), état liaison. La page v1.1
  devient « Bord » (chemin `/dashboard/haku` inchangé — `KIOSK_URL` intact).
- **InfluxDB 2 + Grafana « SD light »** (`INFLUX_ENABLED=1`,
  `GRAFANA_ENABLED=1`) : install.sh étapes 14-15 idempotentes (dépôts
  officiels arm64, sans Docker), setup automatisé (token dans haku.env,
  jamais dans le dépôt), rétention 30 j + downsampling 10 min → 730 j,
  export Node-RED **sans palette** (line protocol fait main, lots 60 s),
  3 dashboards provisionnés (**Traceur** geomap — position 1 pt/min en
  continu —, **Météo bord**, **Électrique**), port **3001** ouvert LAN +
  Tailscale uniquement, `MemoryHigh` 700M/300M.
- **Module Waveshare Modbus POE ETH Relay (B)** (`WAVESHARE_ENABLED=0` par
  défaut) : client **Modbus TCP minimal sans palette** (MBAP fait main sur
  nœud tcp natif, FC01/FC02/FC05, poll DI 2 s / relais 10 s), flotteurs de
  cale commutables Cerbo ↔ Waveshare, bouton Instruments → **relais 1 du
  module** (état FC01 réel, ré-affirmation de tous les relais au démarrage et
  à chaque reconnexion — instruments ON par défaut), alarme « module
  injoignable > 5 min ». Fiche de pose : `FICHE_CABLAGE_Waveshare_Haku.md`.
- **Éclairage extérieur (spreader lights)** : toggle page Bord → **relais 2
  du Cerbo** (`RELAY_LIGHT_INDEX=1`), ré-affirmation 5 min, minuterie
  `LIGHT_AUTO_OFF_MIN`. **L'ancien usage « instruments sur relais Cerbo 2 »
  disparaît** : `INSTR_RELAY_INDEX` ne sert plus qu'en transition
  (`WAVESHARE_ENABLED=0`) et sera retiré dans une version future.
- **Heartbeat dead-man** (`HEALTHCHECK_URL`) : timer systemd 10 min, ping
  seulement si `/health` répond — le silence alerte via healthchecks.io.
- `/health` enrichi (`surv_quai`, `meteo48_last_sample_age_s`, `influx`,
  `waveshare`), pare-feu 3001, nouvelles variables haku.env (voir §4),
  toujours : aucune palette tierce, aucun secret dans le dépôt, verrou COLREG
  intouché et prioritaire, install.sh idempotent, flux protégés par empreinte.

### v1.1.2 (29/08/2026) — mode headless par défaut (`KIOSK_ENABLED=0`, image Lite).
### v1.1.1 — géofence primauté COLREG (jamais d'extinction auto du feu).
### v1.1.0 — Signal K, instruments, traces GPX, carte, flotteurs, commandes.
### v1.0.1 — verrou COLREG, alertes, journal CSV, fiabilité bateau inoccupé.
