# TODO-BANC — v1.2.0 : à valider sur le matériel réel avant de faire confiance

> Liste courte de ce qui n'est PAS vérifiable dans l'environnement de
> développement (pas de module Waveshare, pas de Cerbo, pas de navigateur).
> À dérouler au banc (établi) puis à bord. Les procédures détaillées sont
> dans le README §16 et dans FICHE_CABLAGE_Waveshare_Haku.md.

## Module Waveshare (au banc, AVANT la pose)

- [ ] **Adresses Modbus exactes de CE firmware** : FC01 relais `0x0000-0x0007`,
      FC02 DI `0x0000-0x0007`, FC05 écriture `0xFF00/0x0000` — vérifier avec
      un outil Modbus (ex. `mbpoll -m tcp -t 0 -r 1 -c 8 <ip>` pour les coils,
      `-t 1` pour les DI) que la numérotation part bien de 0 et que l'unit ID
      usine est `1` (certains firmwares répondent aussi à `0xFF`) →
      `WAVESHARE_UNIT_ID`.
- [ ] **Comportement à 8 relais** : écrire relais 1 ON via le flux (appui long
      2 s) et vérifier que SEUL le relais 1 claque ; redémarrer nodered →
      ré-affirmation : relais 1 ON, 2-8 OFF (écouter les claquements).
- [ ] **Tenue de la connexion** : débrancher/rebrancher le RJ45 → réponse en
      moins de ~10 s après retour ; couper l'alim du module 6 min → alerte
      email « module Waveshare injoignable », puis « de retour » + relais 1
      ré-affirmé ON.
- [ ] **Charge des DI en mode wet** : injecter du 24 V sur DI1 (COM au moins)
      → tuile puisard ALARME en ~5 s (avec `WAVESHARE_DI_INVERT=0`).

## Boucles d'alarme du tableau (à bord, ohmmètre)

- [ ] **Polarité de CHAQUE boucle** (folio 11) : tension au point de piquage
      flotteur reposé PUIS levé → en déduire `WAVESHARE_DI_INVERT` (0 ou 1).
      Les 4 boucles doivent avoir la MÊME logique (sinon : mini-relais
      d'interface sur la boucle divergente, cf. fiche §3).
- [ ] **Voyants/buzzer conservés** : après piquage, lever chaque flotteur →
      le tableau réagit comme avant, ET la tuile passe en alarme.

## Chemins Signal K du bord (pour vent 48 h + Influx)

- [ ] `http://<cerbo>:3000` → Data Browser : vérifier la présence de
      `environment.wind.speedTrue` (sinon le graphe utilise l'apparent —
      acceptable au port, à savoir), `environment.outside.pressure`,
      `navigation.position` (indispensable au traceur Influx).

## Rendu Dashboard 2.0 (téléphone, après 30 min de données)

- [ ] **Graphe vent 48 h** : les 3 séries (moyenne bleue, rafales orange,
      seuil rouge) s'affichent, l'axe X est temporel, le `replace` au reboot
      ne crée pas de doublons. (Config `category=property/serie`,
      `x=property/x`, `y=property/y` — validée sur la doc D2, pas en réel.)
- [ ] **Couleurs des tuiles** (msg.class + CSS `site:style`) : zones SEC
      vertes / ALARME rouges, textes sv-good/sv-warn/sv-crit. Si le CSS ne
      « prend » pas (sélecteur span), ajuster tpl_sv_style dans l'éditeur.
- [ ] **Ordre des pages** : /dashboard ouvre bien Surveillance ; Bord et
      Navigations accessibles au menu ; groupe « Eau dans les cales » masqué
      si aucun flotteur configuré.

## InfluxDB / Grafana (sur le Pi réel)

- [ ] Après install.sh : `curl http://127.0.0.1:8086/health` → pass ;
      `INFLUX_TOKEN` et `GRAFANA_ADMIN_PASS` remplis dans haku.env ;
      `influx bucket list` montre haku_raw (30 j) et haku_agg (730 j) ;
      `influx task list` montre haku-downsample-10m.
- [ ] **Geomap « Traceur »** : après 1 h de données, la couche route trace la
      position (plage 1 h puis 24 h) ; si la couche `route` pose problème sur
      la version Grafana installée, basculer la couche en `markers` (2 clics).
- [ ] **RAM** : après 24 h, `systemctl status influxdb grafana-server nodered`
      → mémoire dans les clous (MemoryHigh 700M/300M), Node-RED fluide.
- [ ] **Écritures SD** : `iostat`/`vcgencmd` sur 24 h — confirmer que le mode
      « SD light » reste raisonnable ; sinon avancer le passage SSD
      (INFLUX_DATA_DIR + rsync, README §9 ter).

## Divers v1.2

- [ ] **Dérive SOC** : test accéléré avec `SURV_SOC_H=2` (puis REMETTRE 48) :
      débrancher le quai 2 h avec le toggle actif → email « perd de la
      charge » ; rebrancher → email de rétablissement au retour de charge.
- [ ] **Heartbeat** : check healthchecks.io « up » après 10 min ; stop nodered
      20 min → « down » ; restart → « up ». Vérifier la conso data réelle.
- [ ] **Éclairage extérieur** : WAVESHARE_ENABLED=1 obligatoire ; toggle ON →
      Cerbo Relay 2 claque (fonction Manual dans la console !) ; minuterie
      LIGHT_AUTO_OFF_MIN=1 pour tester l'extinction auto (puis remettre 0).
- [ ] **Seuils à ajuster à l'usage** : WIND_ALERT_KT (35 par défaut — abri du
      port ?), SURV_SOC_DROP (5 points), OFFLINE 5 min du Waveshare.
