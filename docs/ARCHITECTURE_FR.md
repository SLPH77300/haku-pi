# Architecture — Haku Pi

> Haku Pi — version 1.2.0 (30/08/2026, base 27/08/2026)
> Voilier Amel 50 « Haku » — Raspberry Pi 4 Model B, Raspberry Pi OS Bookworm 64-bit (Lite, headless).

v1.1 : le Cerbo est en **Venus OS Large** — son serveur **Signal K (port
3000)** alimente le Pi en WebSocket (instruments, traces GPS, géofence), et
son Node-RED embarqué garde le rôle de **maître du journal de bord** (flow
« Journal auto » du 16/08, intouché) dont le Pi reçoit une copie
(`POST /journal`). Le Pi CONSOMME, il ne duplique pas le journal.

v1.2 : page **Surveillance** par défaut (maquette v5) avec vent 48 h et
alarme dérive SOC à quai ; **InfluxDB 2 + Grafana** locaux « SD light »
(traceur continu 1 pt/min, météo, électrique — port 3001, LAN + Tailscale
uniquement) ; module **Waveshare Modbus TCP** en option (8 DI flotteurs +
8 relais, client Modbus minimal fait main) ; éclairage extérieur sur le
relais 2 du Cerbo ; **heartbeat dead-man** (healthchecks.io). Toujours :
zéro palette tierce, zéro secret dans le dépôt, verrou COLREG prioritaire.

## 1. Vue d'ensemble

```
                                   BORD (LAN du Pepwave, ex. 192.168.8.0/24)
 ┌──────────────────────────────────────────────────────────────────────────┐
 │                                                                          │
 │  ┌────────────────┐   MQTT 1883 (dbus-flashmq)   ┌────────────────────┐  │
 │  │   Cerbo GX     │◄────────────────────────────►│   Raspberry Pi 4   │  │
 │  │  (Venus OS)    │  N/<id>/… lectures           │  Raspberry Pi OS   │  │
 │  │                │  R/<id>/keepalive (30 s)     │  Bookworm Desktop  │  │
 │  │ ├ SmartShunt   │  W/<id>/system/0/Relay/x     │                    │  │
 │  │ ├ MPPT 150/70  │                              │ ├ Node-RED 4       │  │
 │  │ ├ Relais 1 ────┼──► feu de mouillage          │ │ ├ flows Haku     │  │
 │  │ └ (Quattro     │    (câblage à bord)          │ │ └ Dashboard 2.0  │  │
 │  │    24/8000     │                              │ ├ nftables         │  │
 │  │    à venir)    │   ┌───────────────┐  HDMI    │ ├ tailscaled       │  │
 │  └───────┬────────┘   │ Écran du carré│◄─────────┤ └ Chromium kiosk   │  │
 │          │            └───────────────┘          └─────────┬──────────┘  │
 │          │ (VRM, indépendant du Pi)                        │             │
 │  ┌───────┴────────────────────────────────────────────────┐│             │
 │  │              Routeur Peplink/Pepwave (LAN)             ││             │
 │  └───────┬───────────────────────────────┬────────────────┘│             │
 └──────────┼───────────────────────────────┼─────────────────┼─────────────┘
            │ WAN 1 : Starlink (CGNAT)      │ WAN 2 : SIM IT (CGNAT)
            └───────────────┬───────────────┘  failover/agrégation Pepwave
                            ▼
                        INTERNET
                            ▲
            Tailscale : tunnel WireGuard SORTANT du Pi
            (traverse les deux CGNAT ; subnet router → tout le LAN du bord)
                            │
                  Téléphone / PC du propriétaire
                  http://haku:1880/dashboard + Remote Console Cerbo
```

Flux v1.1 supplémentaires (mêmes tuyaux) :

```
Cerbo:3000 (Signal K, WebSocket, abonnement sélectif)
      └──► Pi : cache haku_sk ──► tuiles Instruments (+ rafales, tendance baro)
                    ├──► enregistreur de traces ──► GPX ──► index.geojson ──► carte
                    ├──► GET /api/position (position live de la carte)
                    └──► géofence ports déclarés (notification d'arrivée + alerte dérive
                         — primauté COLREG : jamais d'extinction auto du feu)
Cerbo:Node-RED (flow Journal auto) ──POST /journal──► Pi : haku_journal.jsonl ─┘
Cerbo:MQTT digitalinput/<i>/State (4 flotteurs) ──► tuiles + alertes + CSV
Internet (Open-Meteo, 2x/j) ──► ligne prévisions ;  tuiles OSM/OpenSeaMap ──► carte
```

Flux v1.2 supplémentaires :

```
haku_sk (cache Signal K) ──► échantillonneur 10 min ──► ring 48 h (RAM)
      │                       ├──► graphe vent page Surveillance (replace)
      │                       ├──► meteo48h.json (1 écriture/10 min, tmp+mv)
      │                       └──► alerte WIND_ALERT_KT
      └──► lot line protocol 60 s ──POST──► InfluxDB 127.0.0.1:8086
haku_data (cache MQTT) ──┘        (nav 1 pt/min EN CONTINU + meteo + elec)
InfluxDB ── tâche downsample 10 min ──► bucket 730 j ── Grafana :3001 (geomap…)
SOC (1 échantillon/h si « Surveillance à quai ») ──► alarme dérive SURV_SOC_H
Waveshare (Modbus TCP 502, si WAVESHARE_ENABLED) :
      Pi ──FC02 2 s──► DI1-8 ──► fn_flood (mêmes tuiles/alertes/CSV qu'en MQTT)
      Pi ──FC01 10 s──► état réel relais ──► tuile instruments
      Pi ──FC05──► relais 1 instruments (états voulus persistés, ré-affirmés)
Cerbo Relay 2 (RELAY_LIGHT_INDEX) ◄──MQTT W── toggle éclairage (réaffirmé 5 min)
timer 10 min ── /health OK ? ──curl──► HEALTHCHECK_URL (le SILENCE alerte)
```

Points structurants :

- **Tout le trafic de supervision est local au LAN** (MQTT Pi ↔ Cerbo,
  dashboard, kiosk). Le WAN ne sert qu'aux alertes email, à Tailscale et au
  VRM du Cerbo (indépendant du Pi).
- **Double CGNAT** (Starlink et SIM) : aucune entrée possible → l'accès
  distant repose exclusivement sur un tunnel **sortant** (Tailscale). Une
  bascule WAN du Pepwave est invisible pour le Pi : MQTT est local, Tailscale
  et VRM se reconnectent seuls.
- **Le feu de mouillage reste commandable sans le Pi** : le relais est dans le
  Cerbo (Remote Console → Manual control), et l'interrupteur du tableau reste
  câblable en parallèle. Le Pi est un pilote, pas un point de défaillance
  unique du feu.

## 2. Flux de données MQTT (protocole dbus-flashmq, Venus OS ≥ 3.x)

Vérifié sur le README officiel `victronenergy/dbus-flashmq` et le wiki dbus
Victron ; validé en local contre un simulateur reproduisant le protocole.

| Donnée | Topic (préfixe `N/<portal_id>/`) | Statut |
|---|---|---|
| Découverte portal ID | `system/0/Serial` (retenu) — abonnement `N/+/system/0/Serial` | confirmé + testé |
| SOC | `system/0/Dc/Battery/Soc` | confirmé + testé |
| Tension / courant / puissance batterie | `system/0/Dc/Battery/{Voltage,Current,Power}` | confirmé + testé |
| Température batterie | `system/0/Dc/Battery/Temperature` | confirmé — **TODO-VERIFIER-A-BORD** : n'existe que si l'Aux du SmartShunt est en mode température |
| Puissance solaire | `system/0/Dc/Pv/Power` | confirmé + testé |
| Conso DC | `system/0/Dc/System/Power` | confirmé — **TODO-VERIFIER-A-BORD** : nécessite « Has DC system » |
| Entrée AC active | `system/0/Ac/ActiveIn/Source` (0 n/d, 1 réseau, 2 groupe, 3 quai, 240 inverter) | confirmé (wiki dbus) — absent tant que le Quattro n'est pas posé |
| État système | `system/0/SystemState/State` | confirmé (wiki dbus) |
| Relais feu (lecture) | `system/0/Relay/{0,1}/State` | confirmé + testé |
| Relais feu (écriture) | `W/<id>/system/0/Relay/<RELAY_DBUS_INDEX>/State`, payload `{"value":0|1}`, **sans retain** | confirmé + testé — **TODO-VERIFIER-A-BORD** : index ↔ borne physique (README §6) |
| Keepalive | `R/<id>/keepalive` toutes les 30 s ; payload vide = republication complète, `{"keepalive-options":["suppress-republish"]}` ensuite ; expiration 60 s | confirmé + testé |
| AC connectée (futur Quattro) | `vebus/+/Ac/ActiveIn/Connected` | wiki dbus — inerte tant que pas de vebus |

Stratégie keepalive implémentée : 1er envoi et ~1 envoi sur 20 (≈ 10 min) en
« full » (resynchronisation complète, y compris après reconnexion), le reste
en `suppress-republish` (trafic minimal). La découverte du portal ID force un
« full » immédiat.

## 3. Décisions techniques et justifications

| Décision | Alternatives écartées | Justification |
|---|---|---|
| **MQTT (dbus-flashmq)** pour parler au Cerbo | ModbusTCP, dbus direct, Node-RED sur Venus large | Protocole documenté par Victron, push temps réel, découverte du portal ID, écriture du relais ; ne rien installer sur le Cerbo (stock, mises à jour VRM sereines) |
| **Dashboard 2.0** (`@flowfuse/node-red-dashboard`) | Dashboard 1.0 (déprécié), Grafana | Exigence du propriétaire ; D1 est en fin de vie ; Grafana n'apporte ni widgets de commande ni la simplicité un-seul-service |
| Abonnements **`N/+/…` (wildcard portal)** | topics en dur avec portal ID | Zéro configuration : le flux fonctionne quel que soit le portal ID, découvert au vol sur `system/0/Serial` |
| **Éphéméride NOAA dans un nœud function** | `node-red-contrib-sun-position` | Zéro dépendance : flows.json importable sans nœud de config tiers (un paquet manquant = flux cassé au boot) ; algorithme Meeus/NOAA validé à ± 3 min sur Marseille — largement suffisant pour un feu de mouillage |
| **Email via exec → `send-alert.sh` (curl SMTP)** | `node-red-node-email` | Les credentials des nœuds Node-RED **ne s'exportent pas** dans flows.json : impossible de livrer un flux « prêt à importer » avec l'email intégré. Le script lit tout de `/etc/haku/haku.env` (exigence « paramètres en env »), trace localement, et le flux reste sans aucun secret |
| **journald volatile + /var/log et /tmp en tmpfs** | log2ram | Même effet (zéro écriture de logs sur SD) sans dépôt apt tiers ni service supplémentaire ; Bookworm n'a plus rsyslog par défaut, journald couvre tout ; compensé par l'alerte « Pi redémarré », alerts.log et le CSV (persistants, quelques octets/jour) |
| **nftables natif** (table `inet haku` dédiée) | ufw, iptables | nftables est le pare-feu natif Bookworm ; on ne fait **pas** de `flush ruleset` pour ne jamais écraser les tables de tailscaled (SNAT du subnet router) ; règles validées par `nft -c` avant installation |
| **Kiosk : autostart labwc/wayfire → unité systemd --user** | cage, service system avec Xorg, lightdm autostart X11 | Méthode officielle Pi OS Bookworm (mécanisme utilisé par raspi-config lui-même : `~/.config/labwc/autostart`, wayfire.ini) ; le passage par `systemctl --user` donne la supervision Restart=always à Chromium ; les deux compositors sont couverts (images 2023 → 2025+) |
| **Contexte Node-RED `localfilesystem`** (store `file`, flush 30 s) | fichier à part, EEPROM, retained MQTT | Persistance native du mode MOUILLAGE/MARINA, des états d'alertes et des stats du jour ; testé : le mode survit au reboot ; ≤ 1 écriture/30 s et seulement si modifié |
| **Verrou MARINA ré-affirmé toutes les 5 min** | commande sur changement uniquement | Le Cerbo peut redémarrer, quelqu'un peut basculer le relais à la main : l'état voulu est ré-imposé périodiquement (et immédiatement si la lecture diverge) |
| **Fiabilité à deux étages** : watchdog matériel (15 s) + healthcheck applicatif (2 min) | watchdog seul | Le watchdog matériel couvre les gels noyau/systemd ; il ne voit pas un Node-RED zombie — le healthcheck HTTP `/health` couvre ce cas (3 échecs → restart, 5 cycles → reboot borné à 1/jour) |
| **Alerte « Cerbo silencieux » par âge de données** | statut MQTT seul | Couvre à la fois broker injoignable ET broker connecté mais muet (keepalive perdu, Cerbo planté) |
| **Sauvegardes sur `/boot/firmware` (FAT)** | clé USB, cloud | Lisible sur n'importe quel PC si le Pi meurt ; 7 archives tournantes ; inclut flows, settings, contexte, env (choix documenté et débrayable) et les CSV |
| **Dashboard sans auth, éditeur avec adminAuth** | auth partout | Exigence du propriétaire (consultation immédiate au carré/téléphone) ; le pare-feu limite au LAN + tailnet ; l'éditeur (qui peut exécuter du code) exige un bcrypt |
| **`credentialSecret` fixe non-secret** | clé aléatoire générée | Les flux ne stockent aucun credential (choix email ci-dessus, MQTT LAN sans auth) : la clé ne protège rien ; une valeur fixe évite les invalidations lors des redéploiements ; surchargeable par env |
| **Drop-in systemd `User=/Group=/WorkingDirectory=` rendu par install.sh** | faire confiance à `--nodered-user` de l'installeur | Certaines versions de l'installeur officiel forcent `NODERED_USER=root` quand il tourne en root : le drop-in impose l'utilisateur du bord de façon déterministe (userDir, settings, flows corrects quoi qu'il arrive) ; l'installeur est en plus lancé via `sudo -u` sans `--confirm-root` |
| **Flows protégés par empreinte au redéploiement** | écrasement systématique avec backup | Une ré-exécution d'install.sh/update.sh ne doit pas détruire les éditions faites dans l'éditeur : hash de la dernière version déployée dans `/etc/haku/flows.deployed.sha256`, avertissement au lieu d'écraser si les flux locaux ont divergé |
| **(v1.1) UNE connexion WebSocket Signal K partagée** (subscribe=none + abonnement sélectif) | poll REST, un WS par usage, plugin SK sur le Pi | Ménage le Cerbo (1 Go RAM) : un seul client, 8 chemins ciblés ; instruments, traces, /api/position et géofence lisent tous le cache global `haku_sk` |
| **(v1.1) Leaflet vendu DANS le dépôt** (`static/leaflet/`, servi par httpStatic) | CDN unpkg, téléchargement à l'installation | Zéro CDN à bord (exigence), installation possible sans internet, version figée (1.9.4) ; seules les TUILES OSM/OpenSeaMap exigent internet — limite documentée, dégradation propre |
| **(v1.1) Index carte reconstruit par `tracks-index.py` (exec)** | index incrémental en JS dans les flux | Les function nodes n'ont pas accès au filesystem ; le script Python (stdlib seule) scanne GPX + JSONL, lie trace↔nav à ± 3 h, calcule les stats, écrit atomiquement — même moteur réutilisé par import-journal.py (backfill Caraïbes/Açores) |
| **(v1.1) Moteur de traces sur tick 10 s + contexte 'file'** | subscription position pure, process séparé | Détection départ/arrivée robuste aux trous GPS, intervalle effectif min 10 s (60 s en prod), trace en cours persistée → survit au reboot ; GPX = format d'échange universel |
| **(v1.1) Journal : le Cerbo reste maître** (POST /journal fire-and-forget côté Cerbo) | déplacer le journal sur le Pi | Flow Cerbo opérationnel depuis le 16/08, Google Sheet + CSV = filets existants ; le Pi n'ajoute qu'un puits de données ; patch Cerbo = 2 nœuds, timeout 3 s, échec silencieux |
| **(v1.1) Appui long 2 s via pointerdown/up du bouton D2** | double-clic, dialogue de confirmation custom | Capacité native du ui-button Dashboard 2.0 (enablePointerdown/up) ; mesure de la durée côté serveur — pas de widget tiers (contrainte zéro palette) |
| **(v1.1) Ports déclarés : contexte 'file' + export ports.json (écrit en atomique tmp+mv)** | fichier seul, contexte seul | Le contexte est la source de vérité runtime (atomique, flush 30 s) ; ports.json est l'export lisible/sauvegardé/restaurable (rechargé si contexte vide), jamais corrompu par une coupure |
| **(v1.1.1) Géofence : PRIMAUTÉ COLREG** — notification d'arrivée au port, jamais de bascule automatique hors de MOUILLAGE | MARINA auto à l'entrée du rayon | Un mode MOUILLAGE posé manuellement AVANT l'arrivée (mouillage à < 150 m d'un port déclaré) aurait éteint le feu pendant la nuit — inacceptable règle 30 ; l'humain seul décide d'éteindre |
| **(v1.2) Ring vent 48 h en RAM + snapshot JSON 10 min (tmp+mv)** | context 'file' seul, écriture par échantillon | Exigence « protection SD, ≤ 1 écriture/10 min » tenue exactement ; fichier lisible/sauvegardable dans /var/lib/haku ; graphe rejoué en `replace` complet → zéro doublon après reboot |
| **(v1.2) Alarme dérive SOC : baisse continue sans remontée > 1 pt + seuil SURV_SOC_DROP** | pente moyenne seule | Une remontée = le chargeur travaille (pas de dérive) ; le seuil en points évite d'alerter sur le bruit du SmartShunt ; échantillon horaire persisté 'file' → survit au reboot |
| **(v1.2) InfluxDB 2 + Grafana en paquets natifs arm64, PAS de Docker** | Docker compose, VictoriaMetrics, sqlite | Deux services systemd de plus, zéro couche d'orchestration sur un Pi « bateau inoccupé » ; dépôts officiels signés ; MemoryHigh (700M/300M) garde Node-RED prioritaire ; Influx lié à 127.0.0.1 (rien d'exposé) |
| **(v1.2) Export Influx en line protocol FAIT MAIN + http request natif, lots 60 s** | palette node-red-contrib-influxdb | Doctrine « aucune palette tierce » (un paquet manquant = flux cassé au boot) ; l'API v2 write est un POST texte trivial ; tampon borné 15 min = mémoire sûre, échec silencieux documenté |
| **(v1.2) Traceur = Grafana geomap sur la série `nav` (1 pt/min EN CONTINU)** | grossir le moteur GPX v1.1 | Le sélecteur de plage Grafana remplace toute UI custom ; le GPX v1.1 reste le format d'échange des navigations ; 1 pt/min ≈ 60 Ko/j en base — négligeable |
| **(v1.2) Client Modbus TCP minimal dans un function node sur `tcp request` (mode connexion maintenue)** | palette modbus, passerelle mqtt externe | FC01/02/05 = 12 octets de MBAP à construire : trivial et auditable ; transaction ID vérifié, timeout 1,5 s, transactions séquentielles ; zéro dépendance ; reconnexion gérée par le nœud natif + msg.reset |
| **(v1.2) États voulus des relais Waveshare persistés + ré-affirmés (boot, reconnexion, divergence FC01)** | fire-and-forget des commandes | Une coupure 24 V du module fait retomber les relais : à son retour, les instruments doivent revenir SEULS à ON (circuit de navigation) — même philosophie que le verrou MARINA |
| **(v1.2) Éclairage extérieur actif SEULEMENT si WAVESHARE_ENABLED=1 + garde anti-RELAY_DBUS_INDEX** | toggle toujours actif | Tant que le module n'est pas posé, la borne Cerbo Relay 2 alimente les instruments (v1.1) : un réaffirmeur « éclairage OFF 5 min » aurait coupé les instruments ; et le relais du feu reste sous l'autorité EXCLUSIVE du verrou COLREG |
| **(v1.2) Heartbeat dead-man inversé (ping si /health OK, silence = alerte externe)** | alerte email « je suis mort » (impossible), VRM seul | Un Pi mort ne peut pas s'annoncer mort : seul un service EXTERNE qui attend le ping détecte la disparition totale (Pi, WAN, incendie tableau…) ; healthchecks.io gratuit, ~0,15 Mo/j |

## 4. Fiabilité « bateau inoccupé » — chaîne complète

```
gel noyau/systemd ──► watchdog matériel bcm2835 (15 s) ──► reboot
Node-RED plante   ──► systemd Restart=always (10 s)
Node-RED zombie   ──► healthcheck /health (2 min, ×3) ──► restart nodered
                      └─ 5 cycles KO ──► reboot (≤ 1/jour, uptime > 30 min)
Chromium plante   ──► systemd --user Restart=always (8 s)
Coupure secteur   ──► tout redémarre seul (autologin → kiosk ; nodered enable ;
                      tailscaled enable ; nftables enable ; fsck.repair=yes)
Réseau/MQTT tombe ──► reconnexion infinie (mqttReconnectTime 15 s) + full
                      republish à la reconnexion (keepalive) ; bascule
                      Starlink↔SIM du Pepwave transparente
Cerbo muet        ──► alerte à 15 min + message de rétablissement
Dérive lente      ──► reboot hebdomadaire dim. 04:30 (désactivable), précédé
                      d'une sauvegarde
Usure SD          ──► journald RAM, /var/log + /tmp tmpfs, swap off, cache
                      Chromium en RAM, contexte 1 écriture/30 s max, CSV
                      quelques octets/jour, cartes « endurance » recommandées
```

## 5. Sécurité (modèle en 3 périmètres)

1. **WAN** : rien d'exposé (double CGNAT + nftables policy drop). Tailscale
   uniquement sortant ; UDP 41641 accepté pour permettre le direct WireGuard.
2. **LAN du bord** : SSH (clé uniquement, procédure README) et 1880 seuls
   ouverts, mDNS/DHCP/ICMP utilitaires. Un invité sur le Wi-Fi du bord voit le
   dashboard (assumé) mais pas l'éditeur (bcrypt) ni le shell.
3. **Tailnet** : équivalent LAN pour les machines du propriétaire ; le subnet
   router expose aussi le Cerbo — la route doit être approuvée à la main dans
   la console d'admin.

Secrets : uniquement `/etc/haku/haku.env` (640 root:user) ; dépôt livré sans
aucun secret (placeholders `CHANGEME_*`) ; hash bcrypt généré à bord.

## 6. Budgets

### Énergie (cible bord : 3–6 Ah/j @ 24 V)

| Poste | Puissance | Ah/j @ 24 V |
|---|---|---|
| Pi 4 (Node-RED + MQTT + kiosk actif) | 3,2–4,0 W | 3,2–4,0 |
| Pertes convertisseur 24→5 V (η ≈ 90 %) | 0,4 W | 0,4 |
| **Total Pi** | **3,6–4,4 W** | **≈ 3,6–4,4 Ah/j** ✓ |
| Écran du carré (si allumé en continu) | 10–25 W | 10–25 (à éteindre bateau inoccupé) |

### Data WAN (pertinent quand la SIM italienne est active)

| Flux | Volume |
|---|---|
| MQTT Pi ↔ Cerbo | 0 (local au LAN) |
| Tailscale au repos (keepalives/DERP) | ~3–10 Mo/jour |
| Alerte email | ~5 Ko l'unité |
| Dashboard consulté à distance | ~1–3 Mo/session |
| **Total Pi au repos** | **< 10–15 Mo/jour** |
| (pour mémoire, hors Pi : VRM du Cerbo) | ~quelques dizaines de Mo/mois |
| apt upgrade | centaines de Mo → à faire sous Starlink |

## 7. Validation — ce qui a été testé, ce qui reste à bord

### 7.1 Testé en local (environnement de développement, Node-RED 4 + Dashboard 2.0 v1.30.2 réels)

Un **simulateur de Cerbo** (broker MQTT reproduisant le protocole
dbus-flashmq : Serial retenu, réponse au keepalive par full-publish, écho des
écritures de relais) a permis de valider en conditions réelles :

| Test | Résultat |
|---|---|
| flows.json : JSON valide, 128 nœuds, câblage vérifié par le générateur | OK |
| Démarrage Node-RED : « Started flows », zéro type inconnu, Dashboard 2.0 monté sur `/dashboard`, éditeur verrouillé (401 sans auth) | OK |
| Syntaxe des 30 fonctions JS (`node --check`) et de settings.js | OK |
| Découverte du portal ID via `N/+/system/0/Serial` | OK (`hakuSIM123` affiché, keepalive démarré) |
| Keepalive : 1er payload vide (full), suivants `suppress-republish`, cadence 30 s | OK (observé côté broker) |
| Données batterie/PV/AC/état parsées et exposées (`/health`, dashboard) | OK (SOC vivant, âge < 5 s) |
| **Verrou COLREG** : nuit + mode MOUILLAGE → `W/…/Relay/0/State {"value":1}` **sans retain** ; jour ou MARINA → `{"value":0}` | OK |
| **Persistance du mode** : MOUILLAGE posé, redémarrage complet → mode restauré au boot (t+2 s) | OK |
| Éphéméride NOAA : lever 06:57 / coucher 20:23 (Marseille, 27/08/2026), zénith 55,5° | OK (± 3 min vs éphémérides) |
| **Alerte SOC bas** : SOC forcé à 12 % → email/trace en < 60 s via le vrai `send-alert.sh` (SMTP vide → trace locale, exit 0) | OK (`alerts.log`) |
| **Alerte « Pi redémarré »** à +90 s, conditionnée à un uptime système < 300 s (un simple restart du service nodered n'alerte pas) | OK (`alerts.log`) |
| **Perte du quai** : source AC 3 → 240 à 06:13:31 → alerte « PERTE DU QUAI » à 06:13:40, soit ~5 min 40 s après la disparition réelle de l'AC (seuil 5 min + cadence d'évaluation) ; `/health` liste « Quai perdu » | OK |
| Anti-battement quai : une ré-annonce « quai présent » pendant le débounce annule le chrono (observé lors du premier essai) | OK |
| Anti-doublon : état des alertes persisté sur SD (rappel ≥ 24 h, survit au reboot) | OK (fichier contexte vérifié) |
| `/health` complet (portal, mode, âge MQTT, alertes actives, compteur d'erreurs) | OK |
| shellcheck : install.sh + 6 scripts, **zéro remarque** toutes sévérités ; `nft -c` prêt dans install.sh | OK |

### 7.1 bis — Tests v1.1 (simulateur Cerbo MQTT + mock Signal K WebSocket)

flows.json v1.1 : **208 nœuds, 46 fonctions, 8 onglets, 58 widgets** —
JSON valide, câblage vérifié par le générateur, `node --check` sur les 46
fonctions, boot réel « Started flows » sans erreur ni type manquant.

| Test v1.1 | Résultat |
|---|---|
| Connexion WS Signal K + abonnement sélectif reçu par le mock (8 chemins, périodes 2-10 s) | OK |
| Deltas parsés → `/api/position` live (lat/lon/SOG/cap, fresh) | OK |
| Mini-nav simulée : armement 6 s → trace ouverte → points → immobilité → **GPX clos** (`track-20260827-2027.gpx`) → **index.geojson reconstruit et servi** (stats, LineString) | OK |
| `POST /journal` → `{ok:true}`, JSONL enrichi (`recu_ts`), **fiche liée à la trace** (`journal:true`, ports, SOG max dans les propriétés de la LineString) | OK |
| Leaflet **local** : `/static/leaflet/leaflet.js` 200 (147 Ko), `.css` 200, page `/dashboard/navigations` 200 | OK |
| Flotteur puisard (digitalinput instance 5 → 9) : anti-rebond 3 s → **email « EAU DANS PUISARD »** via le vrai send-alert.sh | OK |
| Géofence (v1.1.1, **primauté COLREG**) : port déclaré sous la position + mode MOUILLAGE posé manuellement → le mode **reste MOUILLAGE** (feu jamais éteint automatiquement), notification d'arrivée émise, ports rechargés depuis ports.json | OK |
| import-journal.py : CSV 3 navs (deg-min `14°28.20'N 60°52.30'W`, décimales à virgule, deg-min à virgule `43°16,50'N`) → 3 entrées JSONL exactes, index 3 features, dédoublonnage vérifié | OK |
| `python3 -m py_compile` sur tracks-index.py + import-journal.py ; shellcheck toujours 0 remarque | OK |

Non testable hors bord (voir §7.2) : rendu DOM de la carte (nécessite un
navigateur — le HTML/JS est servi, Leaflet local répond 200), tuiles OSM
depuis la sandbox, vraies valeurs digitalinput/Signal K du bord.

### 7.1 ter — Tests v1.2 (simulateurs Cerbo MQTT + Signal K + **Waveshare Modbus TCP** + **mock InfluxDB**)

flows.json v1.2.0 : **274 nœuds (65 nouveaux), 58 fonctions, 11 onglets,
3 pages, 13 groupes** — JSON valide, `node --check` sur les 58 fonctions,
câblage/links/groupes vérifiés par script indépendant, diff nœud-à-nœud vs
v1.1.2 : 15 nœuds modifiés (tous voulus), 0 supprimé, **chaîne COLREG
(fn_feu/fn_mode/fn_restore/fn_sun/mq_out_relay/fn_geofence) strictement
intouchée**. Boot réel Node-RED (Dashboard 2.0 v1.30.2) : « Started flows »,
zéro type inconnu, zéro erreur de flux sur toute la session.

Deux simulateurs AJOUTÉS au banc v1.1 : un **module Waveshare simulé**
(serveur Modbus TCP, 8 coils + 8 DI, FC01/02/05, gel/dégel à la demande) et
un **mock d'API InfluxDB** (`POST /api/v2/write` → 204, mode panne 503).

| Test v1.2 | Résultat |
|---|---|
| Pages : `/dashboard` → 301 vers la page par défaut ; `/dashboard/surveillance`, `/haku`, `/navigations` → 200 | OK |
| `/health` v1.2 : `surv_quai`, `meteo48_last_sample_age_s`, `influx{buffered,errors}`, `waveshare{up}`, version | OK |
| Client Modbus : FC02 toutes les 2 s, FC01 toutes les 10 s, transaction ID croissant vérifié côté simulateur | OK |
| **Ré-affirmation au démarrage** : 8 × FC05 dès le premier contact — relais 1 (instruments) **ON**, relais 2-8 OFF | OK |
| **Resynchronisation** : relais 3 forcé ON côté module → FC05 « OFF » au poll FC01 suivant (< 10 s) | OK |
| **Flotteur via DI Waveshare** : DI1 activé → email « EAU DANS PUISARD (entree DI Waveshare) » en **7 s** (poll 2 s + anti-rebond 3 s) via le vrai send-alert.sh | OK (`alerts.log`) |
| **Module injoignable** : gel du simulateur → alerte à exactement **+5 min** ; dégel → email « de retour » immédiat + **ré-affirmation complète des 8 relais** | OK |
| **Influx line protocol** : lots `nav lat=…,lon=…,sog_kn=…`, `meteo gust_kn=…,press_hpa=…`, `elec soc=…,v=…,pv_w=…`, header `Authorization: Token …`, `precision=ms` | OK |
| **Retry borné Influx** : mode panne 503 → tampon 6 points / 2 erreurs (visibles dans `/health`), aucun crash ; rétablissement → purge groupée (lot de 9) puis `buffered: 0` | OK |
| **Échantillon vent 10 min** : frontière d'horloge → `meteo48h.json` écrit (`{ts,w,g,p}`, mv atomique), `/health` expose l'âge | OK |
| **Persistance au reboot** : instance relancée → fn_meteo_load recharge le ring depuis le fichier (échantillon de 307 s d'âge présent dès le boot) | OK |
| Grafana : 3 dashboards + datasource + drop-ins → JSON/YAML valides ; provisioning non exécutable en sandbox (pas d'apt) | OK (statique) |
| install.sh + 8 scripts : `bash -n` + **shellcheck 0 remarque** (toutes sévérités) ; `nft -c` du pare-feu rendu (22/1880/3001) | OK |

Non testable hors bord (complète §7.2) : rendu visuel du graphe D2 multi-séries
(config keyed `serie/x/y` validée sur la doc Dashboard 2.0, pas en réel — voir
TODO-BANC.md), vrai module Waveshare (adresses/unit ID du firmware réel,
polarité des boucles), installation apt InfluxDB/Grafana sur le Pi réel,
tâche de downsampling sur données réelles, geomap Grafana.

### 7.2 À valider à bord (non simulable ici)

Liste exhaustive avec procédures dans le README (§16 « TODO-VERIFIER-A-BORD ») :

1. **Index du relais** `RELAY_DBUS_INDEX` ↔ borne « Relay 1 » (MQTT Explorer + Manual control) — le point le plus important avant de faire confiance au verrou.
2. Topic **température** (Aux SmartShunt en mode température).
3. **Conso DC** (`Has DC system` activé).
4. Topics **AC** réels à l'arrivée du **Quattro** (recette §11.7 : coupure de quai réelle).
5. `video=HDMI-A-1:…` si l'écran du carré est éteint au boot.
6. Curseur kiosk selon présence d'une souris.
7. Précision de l'éphéméride sur zone (2-3 soirs vs Bloc Marine).
8. Kiosk réel labwc sur l'image du bord (méthode = celle de raspi-config, mais non exécutable dans l'environnement de développement).
9. Écriture CSV de 23:55 sur un cycle complet (mécanique nœud file standard, non déclenchée en test local).

## 8. Arborescence déployée sur le Pi

| Source (dépôt) | Déployé vers | Par |
|---|---|---|
| tout le dépôt | `/opt/haku/` | install.sh |
| `config/haku.env.example` | `/etc/haku/haku.env` (si absent) | install.sh |
| `config/settings.js` | `~/.node-red/settings.js` | install.sh |
| `node-red/flows.json` | `~/.node-red/flows.json` | install.sh |
| `config/nftables.conf` (rendu `@SUBNET_BORD@`) | `/etc/nftables.conf` | install.sh |
| `config/journald-haku.conf` | `/etc/systemd/journald.conf.d/10-haku-volatile.conf` | install.sh |
| `config/watchdog-haku.conf` | `/etc/systemd/system.conf.d/10-haku-watchdog.conf` | install.sh |
| `config/tmpfiles-haku.conf` (rendu `@HAKU_USER@`) | `/etc/tmpfiles.d/haku.conf` | install.sh |
| `systemd/nodered-override.conf` | `/etc/systemd/system/nodered.service.d/haku.conf` | install.sh |
| `systemd/haku-*.{service,timer}` | `/etc/systemd/system/` | install.sh |
| `systemd/haku-kiosk.service` | `/etc/systemd/user/` | install.sh |
| ligne autostart kiosk | `~/.config/labwc/autostart` + `~/.config/wayfire.ini` | install.sh |
| données persistantes | `/var/lib/haku/{journal/,alerts.log}` | flux + scripts |
| sauvegardes | `/boot/firmware/haku-backup/haku-*.tar.gz` | haku-backup.timer |
| `static/leaflet/` (vendu, v1.1) | `/opt/haku/static/leaflet/` → servi sur `/static/` | rsync install.sh + httpStatic |
| `cerbo/` (patch journal, v1.1) | import manuel dans le Node-RED du Cerbo | propriétaire (PATCH_Journal_vers_Pi.md) |
| traces + index carte (v1.1) | `/var/lib/haku/tracks/` → servi sur `/tracks/` | flux Traces + tracks-index.py |
| journal de bord (v1.1) | `/var/lib/haku/journal/haku_journal.jsonl` | POST /journal + import-journal.py |
| ports déclarés (v1.1) | `/var/lib/haku/ports.json` | bouton « Déclarer ce port » |
| `config/influxdb-override.conf` (rendu `@INFLUX_DATA_DIR@`, v1.2) | `/etc/systemd/system/influxdb.service.d/haku.conf` | install.sh (14) |
| `config/grafana-override.conf` (rendu `@GRAFANA_PORT@`, v1.2) | `/etc/systemd/system/grafana-server.service.d/haku.conf` | install.sh (15) |
| `config/grafana-datasource.yaml` (rendu org/bucket/`@INFLUX_TOKEN@`, v1.2) | `/etc/grafana/provisioning/datasources/haku.yaml` (640 root:grafana) | install.sh (15) |
| `config/grafana-dashboards.yaml` (v1.2) | `/etc/grafana/provisioning/dashboards/haku.yaml` | install.sh (15) |
| `grafana/dashboards/*.json` (3 dashboards, v1.2) | servis depuis `/opt/haku/grafana/dashboards` | provisioning Grafana |
| `config/influx-downsample.flux` (rendu buckets, v1.2) | tâche `haku-downsample-10m` dans InfluxDB | install.sh (14) |
| `systemd/haku-heartbeat.{service,timer}` (v1.2) | `/etc/systemd/system/` | install.sh (16) |
| ring météo 48 h (v1.2) | `/var/lib/haku/meteo48h.json` (1 écriture/10 min) | flux page Surveillance |
| données InfluxDB (v1.2) | `INFLUX_DATA_DIR` (défaut `/var/lib/haku/influx`) | influxd |
| secrets générés à bord (v1.2) | `INFLUX_TOKEN`, `INFLUX_ADMIN_PASS`, `GRAFANA_ADMIN_PASS` dans `/etc/haku/haku.env` | install.sh (14-15) |
