# Haku Pi — tutoriel complet, pas à pas

*Supervision de bord sur un Raspberry Pi, dialoguant avec un Victron Cerbo GX. Tableau de bord à distance, alertes e-mail, commande à distance des instruments et de l'éclairage, alarmes de cale, sondes d'environnement avec baromètre, feu de mouillage automatique et enregistreur de traces. Construit et exploité sur un Amel 50 en 24 V (« Haku »). Tout propriétaire équipé d'un Cerbo GX peut le reproduire — ce guide suppose que vous savez ouvrir un terminal, pas que vous êtes développeur.*

**English version: [TUTORIAL_EN.md](TUTORIAL_EN.md)**

---

## 0. Avant de commencer — ce que vous obtenez, ce que ça demande

**Ce que vous obtenez, depuis votre téléphone, où que vous soyez :**

| Page | Contenu |
|---|---|
| **Surveillance** | batterie en gros chiffres · **Commandes** : quatre interrupteurs avec chacun une pastille d'état réel (feu de mouillage, instruments, barres de flèche, veille à quai) · vent enregistré 48 h · état de la liaison · alarmes de cale |
| **Bord** | le détail complet : batterie, solaire, quai, instruments et météo, santé du système, historique 24 h |
| **Navigations** | la carte de toutes les navigations du bateau, enregistrées automatiquement |
| **Environnement** | une carte par sonde température/humidité, plus un **baromètre avec tendance sur 3 h** |

**Alertes e-mail :** SOC bas, tension basse, température batterie, perte du quai, pas de pleine charge depuis 14 jours, Cerbo injoignable, eau dans une cale, vent fort, dérive du SOC à quai, température compartiment moteur / frigo / congélateur, **chute rapide de pression** (avis de coup de vent), redémarrage du Pi, module relais injoignable.

**Ce que ça demande :** un week-end, 250 à 350 € de matériel (voir [HARDWARE.md](HARDWARE.md)), des bases en électricité pour deux circuits à relais (voir [WIRING.md](WIRING.md)), et le courage d'ouvrir un terminal.

**Hypothèses :**
- Victron **Cerbo GX** (ou tout GX) sous **Venus OS Large** — Node-RED et Signal K sont intégrés, gratuits.
- Un **SmartShunt ou BMV** pour que le Cerbo connaisse l'état de charge.
- Un **GPS** vu par le Cerbo (NMEA 2000 ou GPS Victron).
- Un **routeur avec Ethernet** à bord et, pour l'accès distant, un accès internet (Starlink, 4G…).
- Un bateau en **12 ou 24 V** — le logiciel s'en moque ; la liste de matériel, non (plages de tension d'entrée).

---

## 1. Architecture — qui fait quoi

```
                    ┌──────────────────────────────────────────────────┐
  Appareils Victron │ Cerbo GX (Venus OS Large)                        │
  SmartShunt, MPPT ─┤  · broker MQTT (batterie, solaire, relais, sondes)│
  Sondes Ruuvi ·····┤  · Signal K    (GPS, vent, sonde, cap)           │
  GPS / NMEA 2000 ──┤  · Node-RED    → FEU DE MOUILLAGE (relais 1)     │◄── le feu de mouillage vit ICI,
                    │                → journal de bord vers Google Sheet│    autonome, sans le Pi
                    └───────────────────────┬──────────────────────────┘
                                            │ Ethernet (câblez-le !)
   ┌────────────────────────────────────────┴────────────────────────────┐
   │                        LAN du bord (votre routeur)                   │
   └──────┬──────────────────────────────┬────────────────────────────────┘
          │                              │
   ┌──────┴───────────┐          ┌───────┴────────────────────┐
   │ Raspberry Pi 4   │ Modbus   │ Module relais Waveshare (B)│
   │  · Node-RED      │◄────────►│  CH1 → instruments (+VHF)  │
   │  · Dashboard     │   TCP    │  CH2 → barres de flèche    │
   │  · alertes       │          │  DI1-4 ← flotteurs de cale │
   │  · traces GPS    │          └────────────────────────────┘
   │  · InfluxDB+Graf.│
   └──────┬───────────┘
          │ Tailscale (tunnel sortant — passe le CGNAT Starlink / 4G)
          ▼
     votre téléphone, n'importe où
```

**Une règle de conception traverse tout le projet : le Pi est l'écran et le messager, jamais la seule sécurité.** Le feu de mouillage fonctionne Pi éteint. Les instruments fonctionnent Pi éteint. Le buzzer de cale du tableau fonctionne Pi éteint. Le Pi *ajoute* la visibilité et la commande à distance ; il ne *remplace* jamais les commandes d'origine du bateau.

---

## 2. Préparer le Raspberry Pi

### 2.1 Flasher le système

1. Téléchargez **Raspberry Pi Imager** sur votre PC.
2. Choisissez **Raspberry Pi OS Lite (64-bit)** — pas de bureau nécessaire.
3. Dans les réglages de l'Imager (roue crantée), **avant d'écrire** :
   - nom d'hôte : `haku` (ou le nom de votre bateau — vous l'utiliserez partout) ;
   - **activer SSH**, par clé publique si vous en avez une, sinon par mot de passe ;
   - utilisateur (ex. `bord`), mot de passe ;
   - langue / fuseau horaire ;
   - **ne pas** configurer le Wi-Fi — le Pi sera en filaire.
4. Écrivez sur la **microSD**, démarrez le Pi avec.

### 2.2 Passer sur SSD (faites-le : une microSD meurt sous journalisation continue)

Le SSD dans son boîtier USB 3, branché sur un port USB **bleu** :

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/billw2/rpi-clone.git && sudo cp rpi-clone/rpi-clone /usr/local/sbin/
lsblk                       # repérer le SSD, en général sda
sudo rpi-clone sda          # répondre yes ; quelques minutes
```

Éteindre, **retirer la microSD**, rallumer. Le Pi démarre sur le SSD. Vérifiez avec `lsblk` que `/` est sur `sda2`.

### 2.3 L'alimentation — à lire deux fois

Un Pi 4 avec SSD demande **5,1 V / 3 A**. Alimenté par une prise USB du bord, il *semble* fonctionner et **se fige en silence toutes les quelques semaines**. Vérifiez vous-même :

```bash
vcgencmd get_throttled
```

`throttled=0x0` est sain. `0x50005` signifie sous-tension **et** bridage **en ce moment même**. Corrigez l'alimentation avant toute autre chose : convertisseur DC-DC dédié, 8–32 V en entrée, 5,1 V / 3 à 5 A en sortie, câble USB-C court et de forte section. Détails dans [HARDWARE.md §2](HARDWARE.md#2-powering-the-pi--the-part-everyone-gets-wrong).

### 2.4 Installer Haku Pi

```bash
git clone https://github.com/SLPH77300/haku-pi.git
cd haku-pi/pi
sudo bash install.sh
```

Le script est **idempotent** — relancez-le autant de fois que nécessaire, il ne modifie que ce qui doit l'être. Il installe Node-RED avec Dashboard 2.0, InfluxDB et Grafana, durcit le système pour un bateau (journaux en RAM, watchdog matériel, redémarrage hebdomadaire, pare-feu), et crée `/etc/haku/haku.env` depuis l'exemple.

Il s'arrête à la fin en vous demandant de configurer `haku.env`. C'est l'étape 4.

---

## 3. Réseau — que les trois appareils se voient

Le Pi, le Waveshare et le Cerbo doivent être sur le **même LAN filaire**.

1. **Ethernet pour les trois.** La plupart des routeurs de bord n'ont qu'un ou deux ports LAN ; ajoutez un **switch 5 ports** (voir [HARDWARE.md §4](HARDWARE.md#4-network)).
2. **Câblez le Cerbo — ne le laissez pas en Wi-Fi.** Venus OS **n'a aucun réglage de priorité Wi-Fi** : il se connecte au réseau connu le plus fort et n'en revient jamais. Avec un second Wi-Fi à portée (Starlink, box 4G), votre Cerbo ira s'y perdre et disparaîtra du LAN. Nous l'avons perdu deux fois en trois jours avant de le câbler. L'Ethernet est toujours prioritaire sur un GX.
3. **Adresses fixes** — réservez-les dans le DHCP de votre routeur par adresse MAC : le Pi, le Cerbo, le Waveshare. Notez-les. Deux d'entre elles vont dans `haku.env`.
4. **Accès distant :** créez un compte [Tailscale](https://tailscale.com) (gratuit), générez une *auth key*, mettez-la dans `haku.env` (`TS_AUTHKEY`). Le Pi ouvre un tunnel sortant ; vous atteignez le dashboard depuis votre téléphone à travers le CGNAT de Starlink ou d'un opérateur 4G, sans aucune redirection de port. Dans la console Tailscale, **approuvez la route de sous-réseau** et **désactivez l'expiration de clé** pour le Pi.

---

## 4. Cerbo GX — activer ce dont le Pi a besoin

Sur la Remote Console du Cerbo (**Settings**) :

| Réglage | Valeur | Pourquoi |
|---|---|---|
| **Services → MQTT on LAN (plaintext)** | On | le Pi lit tout en MQTT |
| **Services → Node-RED** | Enabled | pour le flux du feu de mouillage (Venus OS **Large** requis) |
| **Services → Signal K** | Enabled | GPS, vent, sonde pour les traces et les instruments |
| **Relay → Function (Relay 1)** | **Manual** | sinon les écritures de Node-RED sur le relais sont ignorées |
| **Integrations → Bluetooth sensors** | vos Ruuvi, nommés | les noms saisis ici apparaissent tels quels sur la page Environnement |

> ⚠️ **Après chaque mise à jour de Venus OS**, ouvrez le Node-RED du Cerbo (`https://venus.local:1881`) et vérifiez qu'il n'est pas en **mode sans échec**. Ça nous est arrivé après la 3.79 : feu de mouillage et journal de bord arrêtés en silence pendant plusieurs jours. Cliquez **Deploy**, ça repart.

---

## 5. Configurer `haku.env`

```bash
sudo nano /etc/haku/haku.env
```

Le fichier est commenté ligne par ligne. Celles qui comptent pour démarrer :

```bash
CERBO_HOST=192.168.x.x            # IP fixe du Cerbo (plus fiable que venus.local au démarrage)
SIGNALK_URL=ws://192.168.x.x:3000/signalk/v1/stream?subscribe=none
HAKU_LAT=43.27                    # position approximative, utilisée seulement avant le GPS
HAKU_LON=5.35
TZ=Europe/Paris

SMTP_HOST=smtp.gmail.com          # n'importe quel SMTP ; pour Gmail, créer un « mot de passe d'application »
SMTP_USER=vous@gmail.com
SMTP_PASS=xxxx-xxxx-xxxx-xxxx
SMTP_FROM=haku-pi@votredomaine
SMTP_TO=vous@gmail.com

TS_AUTHKEY=tskey-auth-...         # Tailscale
SUBNET_BORD=192.168.x.0/24        # votre LAN de bord

WAVESHARE_ENABLED=0               # laisser à 0 tant que le module n'est pas installé (étape 6)
```

Puis définissez le mot de passe de l'éditeur Node-RED (le dashboard est ouvert sur le LAN, l'*éditeur* est protégé) :

```bash
sudo /opt/haku/scripts/gen-adminauth.sh
sudo bash install.sh                 # relancer pour tout appliquer
```

Ouvrez **`http://haku:1880/dashboard/haku`** sur un téléphone connecté au Wi-Fi du bord. La page Surveillance doit afficher des données batterie réelles en moins d'une minute.

---

## 6. Le module relais Waveshare

### 6.1 Premier contact

Le module sort d'usine en **192.168.1.254** (certains lots 192.168.1.200) : il n'apparaîtra donc pas sur votre LAN. Utilisez l'outil **VirCom** de Waveshare sur un PC Windows branché sur le même switch — son *Auto Search* trouve le module même sur un autre sous-réseau. Réglez :

- une **IP fixe** sur votre LAN (à réserver aussi dans le routeur),
- **Modbus TCP**, port **502**, unit ID **1**,
- le mode passerelle **« Multi-host non-storage »** (défaut usine — vérifiez),
- **ne touchez pas aux paramètres série** (115200/8/N/1) : la notice prévient que ça coupe la communication.

> Les LED du RJ45 de ce module **ne sont pas des témoins de lien**. Vert = une connexion TCP est établie, jaune = trafic. Les deux éteintes est normal tant qu'aucun logiciel n'est connecté. Les vrais signes de vie sont **RUN** (rouge, clignote toutes les 2 s) et **STA**. Nous avons cherché une heure une panne qui n'existait pas.

### 6.2 Le déclarer au Pi

```bash
WAVESHARE_ENABLED=1
WAVESHARE_HOST=192.168.x.x
WAVESHARE_PORT=502
WAVESHARE_UNIT_ID=1
WAVESHARE_INSTR_RELAY=1           # voie des instruments
WAVESHARE_LIGHT_RELAY=2           # voie des barres de flèche
WAVESHARE_INSTR_CONTACT=NO        # NO ou NC — ce que vous avez réellement câblé (étape 6.3)
WAVESHARE_LIGHT_CONTACT=NO
```

`sudo systemctl restart nodered`, puis `curl http://127.0.0.1:1880/health` doit montrer `"waveshare": {"up": true}`.

### 6.3 Câbler les deux circuits

Tout l'électrique — où va le relais, NO ou NC, calibres de fusibles, connecteurs, sécurité — est dans **[WIRING.md](WIRING.md)**. Lisez-le entièrement avant d'ouvrir le tableau. En résumé : le relais s'insère **en série après le disjoncteur du circuit**, jamais sur le bus commun du tableau ; **décidez pour chaque circuit ce que « module mort » doit produire** et choisissez NO ou NC en conséquence ; **protégez la liaison** par un fusible côté COM.

Les variables `*_CONTACT` **décrivent** votre câblage, elles ne le changent pas. Si un interrupteur du dashboard fonctionne à l'envers, vous avez mis la mauvaise valeur.

### 6.4 Flotteurs de cale (optionnel)

Les 8 entrées opto-isolées lisent vos boucles d'alarme 24 V existantes en parallèle — le buzzer du tableau continue de fonctionner. Mesurez chaque boucle avant de raccorder, réglez `WAVESHARE_DI_INVERT`. Détails dans [REFERENCE_FR.md](REFERENCE_FR.md).

---

## 7. Le feu de mouillage automatique (sur le Cerbo, pas sur le Pi)

Celui-ci tourne **entièrement sur le Cerbo** : il continue de fonctionner Pi mort. Ce flux a son propre dépôt — guide complet en français et en anglais, schémas de câblage, 18 tests unitaires : **[https://github.com/SLPH77300/anchor-light-auto-cerbo-amel](https://github.com/SLPH77300/anchor-light-auto-cerbo-amel)**. Le flux livré ici est cette même v3.1.

1. Câblez le feu de mouillage sur le **Relais 1** du Cerbo, en parallèle de l'interrupteur d'origine (l'interrupteur garde la priorité).
2. Ouvrez le Node-RED du Cerbo : `https://venus.local:1881`. Menu → Import → collez le contenu de **`cerbo/anchor-light-v3.1.flow.json`** → Deploy.
3. Ouvrez le nœud **`Cerbo Relay 1`**, sélectionnez votre appareil Venus et `Venus relay 1 state`, Deploy à nouveau.
4. À votre port d'attache, cliquez une fois l'inject **« Set home port HERE »**. La position est enregistrée sur le Cerbo. **Tant que ce n'est pas fait, le feu reste verrouillé ÉTEINT** — c'est voulu, aucun port par défaut n'est livré. Les injects **« TEST relay ON / OFF »** servent à vérifier le câblage ; le flux ré-affirme le relais toutes les 5 min.

Le feu s'allume **30 minutes avant le coucher du soleil**, uniquement **au mouillage** (SOG < 1 nd) **et hors du port** (> 3 NM), et s'éteint au lever. La règle 30 du RIPAM, automatisée.

**Important :** l'interrupteur *Mooring* du dashboard du Pi **ne commande pas** ce relais. Deux programmes écrivant sur le même relais a été notre pire bug (le Pi éteignait le feu au mouillage, en silence). Le Cerbo est le maître unique ; le Pi ne fait qu'*afficher* l'état réel du relais. Donner au Pi un vrai canal « forcer allumé » est dans la feuille de route.

---

## 8. Le dashboard — comment le lire

### Le bloc Commandes

```
🟢  Mooring         [====O]     ← feu de mouillage : état lu sur le relais du Cerbo
⚪  Instruments     [O====]     ← CH1
⚪  Spreader        [O====]     ← CH2
⚪  Veille quai     [O====]     ← mode surveillance à quai (logiciel)
[         Déclarer le port         ]
```

La pastille **n'est pas un écho de l'interrupteur**. Elle est relue indépendamment — Modbus FC01 pour les relais Waveshare, MQTT pour le relais Cerbo — et peut donc attraper une commande qui n'a pas pris :

| Pastille | Sens |
|---|---|
| 🟢 | commandé ON et confirmé ON |
| ⚪ | éteint |
| 🟠 | en attente de confirmation, ou module / Cerbo injoignable |
| 🔴 | **commandé ON, lu OFF depuis plus de 60 s** |

Limite honnête : elle reflète le **relais**, pas la charge. Un disjoncteur tombé en aval affiche toujours vert. Une entrée digitale piquée en aval de chaque circuit lèverait cette limite — quatre entrées sont libres.

### Page Environnement

Une carte par sonde, nommée comme dans VRM. Une sonde silencieuse depuis 15 min passe en gris pointillé — une pile Ruuvi qui faiblit se voit avant d'être morte. Le bandeau du haut est le **baromètre** : pression et variation sur 3 heures. Il passe orange à **−3 hPa/3 h** (un coup de vent arrive) et rouge à **−5 hPa/3 h** (il arrive vite). La pression absolue dit peu de choses ; c'est la *vitesse* qui prévoit.

---

## 9. Alertes — ce qui se déclenche et comment l'ajuster

Tous les seuils sont dans `haku.env`. Défauts :

| Alerte | Déclenchement | Variable |
|---|---|---|
| SOC bas | < 30 % | `ALERT_SOC_MIN` |
| Tension basse | < 24,8 V | `ALERT_VBAT_MIN` |
| Pas de pleine charge | 14 jours sans atteindre 28,4 V pendant 10 min | `FULLCHARGE_*` |
| Quai perdu | > 5 min | `ALERT_AC_LOSS_MIN` |
| Cerbo injoignable | > 15 min | `CERBO_TIMEOUT_MIN` |
| Vent fort | > 35 nd | `WIND_ALERT_KT` |
| Dérive SOC à quai | −5 pts en 48 h, veille à quai active | `SURV_SOC_*` |
| Compartiment moteur | > 60 °C (45 °C en veille à quai) | `TEMP_ALERT_RULES` |
| Congélateur / frigo | > −10 °C / > 14 °C, **tenu 30 min** | `TEMP_ALERT_RULES`, `TEMP_ALERT_DELAY_MIN` |
| Chute de pression | −3 hPa/3 h vigilance, −5 alerte | `BARO_DROP_WATCH`, `BARO_DROP_ALERT` |

Chaque alerte a un message de **retour à la normale** et un rappel à 24 h (`ALERT_REMIND_H`). Les règles de température s'appuient sur un fragment du nom de la sonde : renommer une sonde dans VRM suffit à la recibler.

Testez toute la chaîne avec le bouton **« Tester l'alerte email »** de la page Bord.

---

## 10. Recette de test — avant de lui faire confiance

| # | Faire | Attendu |
|---|---|---|
| 1 | Débrancher l'Ethernet du Cerbo 20 min | e-mail « Cerbo injoignable », puis « de retour » |
| 2 | Interrupteur Instruments OFF puis ON | le relais claque, pastille ⚪ puis 🟢 sous 5 s |
| 3 | Interrupteur Spreader ON | lumière allumée, pastille 🟢 |
| 4 | `sudo systemctl restart nodered` | chaque relais ré-affirmé dans l'état voulu ; les circuits NC ne clignotent jamais |
| 5 | Couper l'alimentation du Waveshare 6 min | e-mail « module injoignable », pastilles 🟠 ; les circuits NC restent alimentés, les NO s'éteignent |
| 6 | Lever un flotteur de cale à la main | tuile ALARME, e-mail sous 5 s, le buzzer du tableau sonne toujours |
| 7 | Bouton de test d'alerte | un e-mail |
| 8 | Au mouillage au crépuscule, à plus de 3 NM du port | feu allumé ~30 min avant le coucher, éteint au lever |
| 9 | Depuis le téléphone en 4G, Wi-Fi coupé | le dashboard se charge via Tailscale |
| 10 | Couper l'alimentation du Pi, attendre, rebrancher | tout revient en 2 min, sans intervention |

---

## 11. Dépannage — les leçons qu'on a payées

**Le Cerbo disparaît du LAN.** Il est en Wi-Fi et a migré vers un réseau plus fort. Câblez-le (§3). En attendant : Settings → Wi-Fi → *oublier* l'autre réseau.

**Feu de mouillage et journal arrêtés après une mise à jour Venus OS.** Node-RED a redémarré en mode sans échec. `https://venus.local:1881` → Deploy.

**Le Pi se fige toutes les quelques semaines.** Sous-tension. `vcgencmd get_throttled` ≠ `0x0` → corrigez l'alimentation (§2.3).

**Un interrupteur du dashboard fonctionne à l'envers.** `WAVESHARE_*_CONTACT` ne correspond pas à ce que vous avez câblé. Changez la variable, redémarrez Node-RED. Ne touchez pas aux fils.

**Le feu de mouillage s'allume au port d'attache.** Le port n'est pas défini sur le Cerbo. Cliquez « Définir le port ici » au port.

**« Waveshare injoignable » mais les LED du RJ45 sont éteintes.** Ce ne sont pas des témoins de lien — voir §6.1. Vérifiez RUN/STA, puis l'IP.

**Un fusible de liaison saute quand vous émettez à la VHF.** Vous l'avez dimensionné sur la veille. Une VHF 25 W tire ~3 A côté 24 V en émission. 6 à 7,5 A sur ce circuit.

**Les pastilles passent sous les interrupteurs sur votre téléphone.** Ça ne devrait plus arriver depuis la v1.3 (la pastille fait partie du libellé). Si vous personnalisez le dashboard : sous 576 px, Dashboard 2.0 rend les groupes en **3 colonnes** ; deux widgets côte à côte se replieront toujours. Un widget par ligne.

**« Aucune sonde reçue » sur la page Environnement.** MQTT est coupé (Cerbo injoignable) ou vos sondes ne sont pas déclarées sur le Cerbo (Settings → Integrations).

---

## 12. Maintenance

- **Sauvegardes** chaque nuit dans `/boot/firmware/haku-backup` (flows, journal, traces, ports, `haku.env`). C'est sur le *même* SSD — copiez ce dossier hors du bateau régulièrement (`scp -r bord@haku:/boot/firmware/haku-backup .`). Une vraie sauvegarde hors bord est dans la feuille de route.
- **Mise à jour :** `cd haku-pi && git pull && cd pi && sudo bash install.sh`.
- **Santé :** `curl http://haku:1880/health` — un JSON avec tout ce qui compte ; `flow_errors` doit être à 0.
- **Redémarrage hebdomadaire** programmé (dimanche 04 h 30) — un Pi laissé seul des mois apprécie.

---

## 13. Feuille de route / pas encore fait

- Un vrai canal « forcer allumé / auto » du Pi vers le flux feu de mouillage du Cerbo.
- Des entrées digitales en aval de chaque circuit commuté, pour que les pastilles prouvent que la *charge* est alimentée, pas seulement le relais.
- Sauvegarde hors bord (cloud), complète et permanente.
- Redémarrage à froid du Pi à distance via un relais du Cerbo — le seul remède qui a marché le jour où le Pi s'est figé.
- Niveaux d'eau et de gasoil.

---

*Questions, améliorations, autres bateaux : ouvrez une issue. Si ça vous épargne les week-ends que ça nous a coûtés, ça valait la peine de le publier.*
