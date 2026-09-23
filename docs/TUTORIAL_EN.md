# Haku Pi — full step-by-step tutorial

*Boat supervision on a Raspberry Pi, talking to a Victron Cerbo GX. Remote dashboard, e-mail alerts, remote switching of instruments and lights, bilge alarms, environment sensors with a barometer, an automatic anchor light and a track recorder. Built and run on a 24 V Amel 50 ("Haku"). Any owner with a Cerbo GX can reproduce it — this guide assumes you can use a terminal but does not assume you are a developer.*

**Version française : [TUTORIEL_FR.md](TUTORIEL_FR.md)**

---

## 0. Before you start — what you'll get and what it takes

**What you get, from your phone, anywhere:**

| Page | Content |
|---|---|
| **Surveillance** | battery in big digits · **Commands**: four switches with a live status dot each (anchor light, instruments, spreader lights, dock-watch mode) · 48 h wind log · link status · bilge alarms |
| **Bord** (on board) | full detail: battery, solar, shore power, instruments and weather, system health, 24 h history |
| **Navigations** | a map of every passage the boat has made, recorded automatically |
| **Environnement** | one card per temperature/humidity sensor, plus a **barometer with 3-hour trend** |

**E-mail alerts:** low SOC, low voltage, battery temperature, shore power lost, no full charge for 14 days, Cerbo unreachable, water in a bilge, strong wind, SOC drifting at the dock, engine room / fridge / freezer temperature, **pressure dropping fast** (gale warning), Pi rebooted, relay module unreachable.

**What it takes:** a weekend, ~250–350 € of hardware (see [HARDWARE.md](HARDWARE.md)), basic electrical skills for two relay circuits (see [WIRING.md](WIRING.md)), and the courage to open a terminal.

**Assumptions:**
- Victron **Cerbo GX** (or any GX device) with **Venus OS Large** — Node-RED and Signal K are built in, free.
- A **SmartShunt or BMV** so the Cerbo knows the state of charge.
- A **GPS** visible to the Cerbo (NMEA 2000 or a Victron GPS).
- A **router with Ethernet** on board and, for remote access, some internet (Starlink, 4G…).
- A boat in **12 or 24 V** — the software doesn't care; the hardware list does (input voltage ranges).

---

## 1. Architecture — who does what

```
                    ┌──────────────────────────────────────────────────┐
  Victron devices   │ Cerbo GX (Venus OS Large)                        │
  SmartShunt, MPPT ─┤  · MQTT broker  (battery, solar, relays, sensors)│
  Ruuvi sensors ····┤  · Signal K     (GPS, wind, depth, heading)      │
  GPS / NMEA 2000 ──┤  · Node-RED     → ANCHOR LIGHT (relay 1)         │◄── the anchor light lives HERE,
                    │                 → logbook to Google Sheets        │    autonomous, no Pi needed
                    └───────────────────────┬──────────────────────────┘
                                            │ Ethernet (wire it!)
   ┌────────────────────────────────────────┴────────────────────────────┐
   │                        boat LAN  (your router)                       │
   └──────┬──────────────────────────────┬────────────────────────────────┘
          │                              │
   ┌──────┴───────────┐          ┌───────┴────────────────────┐
   │ Raspberry Pi 4   │ Modbus   │ Waveshare relay module (B) │
   │  · Node-RED      │◄────────►│  CH1 → instruments (+VHF)  │
   │  · Dashboard     │   TCP    │  CH2 → spreader lights     │
   │  · alerts        │          │  DI1-4 ← bilge floats      │
   │  · track recorder│          └────────────────────────────┘
   │  · InfluxDB+Graf.│
   └──────┬───────────┘
          │ Tailscale (outbound tunnel — works through Starlink/4G CGNAT)
          ▼
     your phone, anywhere
```

**One design rule runs through everything: the Pi is the screen and the messenger, never the only safety.** The anchor light keeps working with the Pi off. The instruments keep working with the Pi off. The bilge buzzer on the panel keeps working with the Pi off. The Pi *adds* remote visibility and remote control; it never *replaces* the boat's original controls.

---

## 2. Prepare the Raspberry Pi

### 2.1 Flash the system

1. Download **Raspberry Pi Imager** on your PC.
2. Choose **Raspberry Pi OS Lite (64-bit)** — no desktop needed.
3. In the Imager's settings (gear icon) **before writing**:
   - hostname: `haku` (or your boat's name — you'll use it everywhere);
   - **enable SSH**, with a **public key** if you have one, otherwise a password;
   - username (e.g. `bord`), password;
   - locale/timezone;
   - **do not** configure Wi-Fi — the Pi will be wired.
4. Write to the **microSD**, boot the Pi with it.

### 2.2 Move to the SSD (do this — a microSD dies under continuous logging)

With the SSD in its USB 3 enclosure plugged into a **blue** USB port:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/billw2/rpi-clone.git && sudo cp rpi-clone/rpi-clone /usr/local/sbin/
lsblk                       # find the SSD, usually sda
sudo rpi-clone sda          # answer yes; takes a few minutes
```

Power off, **remove the microSD**, power on. The Pi now boots from the SSD. Check with `lsblk` that `/` is on `sda2`.

### 2.3 Power — read this twice

A Pi 4 + SSD needs **5.1 V / 3 A**. Powered from a boat USB socket it will *appear* to work and **freeze silently every few weeks**. Check for yourself:

```bash
vcgencmd get_throttled
```

`throttled=0x0` is healthy. `0x50005` means under-voltage **and** throttling **right now**. Fix the power before anything else: dedicated DC-DC converter, 8–32 V in, 5.1 V / 3–5 A out, short thick USB-C cable. Details in [HARDWARE.md §2](HARDWARE.md#2-powering-the-pi--the-part-everyone-gets-wrong).

### 2.4 Install Haku Pi

```bash
git clone https://github.com/SLPH77300/haku-pi.git
cd haku-pi/pi
sudo bash install.sh
```

The script is **idempotent** — run it again any time, it only changes what needs changing. It installs Node-RED with Dashboard 2.0, InfluxDB and Grafana, hardens the system for a boat (logs in RAM, hardware watchdog, weekly reboot, firewall), and creates `/etc/haku/haku.env` from the example.

It will stop at the end and tell you to configure `haku.env`. That's step 4.

---

## 3. Network — make the three devices see each other

The Pi, the Waveshare and the Cerbo must be on the **same wired LAN**.

1. **Ethernet for all three.** Most boat routers have one or two LAN ports; add a **5-port switch** (see [HARDWARE.md §4](HARDWARE.md#4-network)).
2. **Wire the Cerbo — do not leave it on Wi-Fi.** Venus OS has **no Wi-Fi priority setting**: it connects to the strongest known network and never comes back. With a second Wi-Fi around (Starlink, a 4G box), your Cerbo will wander and vanish from the LAN. We lost it twice in three days before wiring it. Ethernet always has priority on a GX device.
3. **Fixed addresses** — reserve them in your router's DHCP by MAC address: the Pi, the Cerbo, the Waveshare. Write them down. You'll put two of them in `haku.env`.
4. **Remote access:** create a free [Tailscale](https://tailscale.com) account, generate an *auth key*, put it in `haku.env` (`TS_AUTHKEY`). The Pi opens an outbound tunnel; you reach the dashboard from your phone through Starlink's or a 4G carrier's CGNAT without any port forwarding. In the Tailscale admin console, **approve the advertised subnet route** and **disable key expiry** for the Pi.

---

## 4. Cerbo GX — enable what the Pi needs

On the Cerbo's Remote Console (**Settings**):

| Setting | Value | Why |
|---|---|---|
| **Services → MQTT on LAN (plaintext)** | On | the Pi reads everything over MQTT |
| **Services → Node-RED** | Enabled | for the anchor light flow (needs Venus OS **Large**) |
| **Services → Signal K** | Enabled | GPS, wind, depth for the track recorder and instruments |
| **Relay → Function (Relay 1)** | **Manual** | otherwise Node-RED's writes to the relay are ignored |
| **Integrations → Bluetooth sensors** | your Ruuvi tags, named | names appear on the Environnement page as typed here |

> ⚠️ **After every Venus OS update**, open the Cerbo's Node-RED (`https://venus.local:1881`) and check it isn't in **safe mode**. It happened to us after 3.79: the anchor light and the logbook were silently stopped for days. Click **Deploy** and it restarts.

---

## 5. Configure `haku.env`

```bash
sudo nano /etc/haku/haku.env
```

The file is commented line by line. The ones that matter to start:

```bash
CERBO_HOST=192.168.x.x            # the Cerbo's fixed IP (more reliable than venus.local at boot)
SIGNALK_URL=ws://192.168.x.x:3000/signalk/v1/stream?subscribe=none
HAKU_LAT=43.27                    # rough position, used only until GPS data arrives
HAKU_LON=5.35
TZ=Europe/Paris

SMTP_HOST=smtp.gmail.com          # any SMTP; for Gmail create an "app password"
SMTP_USER=you@gmail.com
SMTP_PASS=xxxx-xxxx-xxxx-xxxx
SMTP_FROM=haku-pi@yourdomain
SMTP_TO=you@gmail.com

TS_AUTHKEY=tskey-auth-...         # Tailscale
SUBNET_BORD=192.168.x.0/24        # your boat LAN

WAVESHARE_ENABLED=0               # leave 0 until the module is installed (step 6)
```

Then set the Node-RED editor password (the dashboard itself is open on the LAN, the *editor* is protected):

```bash
sudo /opt/haku/scripts/gen-adminauth.sh
sudo bash install.sh                 # re-run to apply everything
```

Open **`http://haku:1880/dashboard/haku`** on a phone on the boat's Wi-Fi. You should see the Surveillance page with live battery data within a minute.

---

## 6. The Waveshare relay module

### 6.1 First contact

The module ships on **192.168.1.254** (some batches 192.168.1.200) and therefore won't show up on your LAN. Use Waveshare's **VirCom** tool on a Windows PC plugged into the same switch — its *Auto Search* finds the module even on another subnet. Set:

- a **fixed IP** on your LAN (and reserve it in the router too),
- **Modbus TCP**, port **502**, unit ID **1**,
- gateway mode **"Multi-host non-storage"** (factory default — check it),
- **do not touch the serial settings** (115200/8/N/1): the manual warns it breaks communication.

> The RJ45 LEDs on this module are **not link LEDs**. Green = a TCP connection is established, yellow = traffic. Both dark is normal until software connects. The signs of life are **RUN** (red, blinks every 2 s) and **STA**. We spent an hour hunting a fault that didn't exist.

### 6.2 Tell the Pi

```bash
WAVESHARE_ENABLED=1
WAVESHARE_HOST=192.168.x.x
WAVESHARE_PORT=502
WAVESHARE_UNIT_ID=1
WAVESHARE_INSTR_RELAY=1           # channel for the instruments
WAVESHARE_LIGHT_RELAY=2           # channel for the spreader lights
WAVESHARE_INSTR_CONTACT=NO        # NO or NC — what you actually wired (step 6.3)
WAVESHARE_LIGHT_CONTACT=NO
```

`sudo systemctl restart nodered`, then `curl http://127.0.0.1:1880/health` must show `"waveshare": {"up": true}`.

### 6.3 Wire the two circuits

Everything electrical — where the relay goes, NO vs NC, fuse ratings, connectors, safety — is in **[WIRING.md](WIRING.md)**. Read it entirely before opening the panel. The short version: the relay goes **in series after the circuit's breaker**, never on the panel's common bus; **decide per circuit what "module dead" should do** and pick NO or NC accordingly; **fuse the link** on the COM side.

The `*_CONTACT` variables **describe** your wiring, they don't change it. If a switch on the dashboard works backwards, you set the wrong one.

### 6.4 Bilge float switches (optional)

The 8 opto-isolated inputs read your existing 24 V alarm loops in parallel — the panel's buzzer keeps working. Measure each loop before connecting, set `WAVESHARE_DI_INVERT`. Details in [REFERENCE_FR.md](REFERENCE_FR.md) (French).

---

## 7. The automatic anchor light (on the Cerbo, not the Pi)

This one runs **entirely on the Cerbo**, so it keeps working if the Pi is dead. This flow has its own repository — full guide in English and French, wiring diagrams, 18 unit tests: **[https://github.com/SLPH77300/anchor-light-auto-cerbo-amel](https://github.com/SLPH77300/anchor-light-auto-cerbo-amel)**. The flow shipped here is that same v3.1.

1. Wire the anchor light through the Cerbo's **Relay 1**, in parallel with the original switch (the switch keeps priority).
2. Open the Cerbo's Node-RED: `https://venus.local:1881`. Menu → Import → paste the content of **`cerbo/anchor-light-v3.1.flow.json`** → Deploy.
3. Open the **`Cerbo Relay 1`** node, select your Venus device and `Venus relay 1 state`, Deploy again.
4. At your home berth, click the **"Set home port HERE"** inject once. The position is saved on the Cerbo. **Until you do, the light stays locked OFF** — by design, no default port ships. The **"TEST relay ON / OFF"** injects let you check the wiring; the flow re-asserts the relay every 5 min.

The light comes on **30 minutes before sunset**, only when **anchored** (SOG < 1 kn) **and away from home** (> 3 NM), and goes off at sunrise. Rule 30 of the COLREGs, automated.

**Important:** the Pi's dashboard switch labelled *Mooring* does **not** command this relay. Two programs writing the same relay was our worst bug (the Pi silently switched the light off at anchor). The Cerbo is the single master; the Pi only *displays* the relay's real state. Giving the Pi a proper "force on" channel is on the roadmap.

---

## 8. The dashboard — how to read it

### The Commands block

```
🟢  Mooring         [====O]     ← anchor light: state read from the Cerbo relay
⚪  Instruments     [O====]     ← CH1
⚪  Spreader        [O====]     ← CH2
⚪  Veille quai     [O====]     ← dock-watch mode (software)
[         Déclarer le port         ]
```

The dot **is not an echo of the switch**. It's read back independently — Modbus FC01 for the Waveshare relays, MQTT for the Cerbo relay — so it can catch a command that didn't take:

| Dot | Meaning |
|---|---|
| 🟢 | commanded ON and confirmed ON |
| ⚪ | off |
| 🟠 | waiting for confirmation, or module/Cerbo unreachable |
| 🔴 | **commanded ON, read OFF for more than 60 s** |

Honest limit: it reflects the **relay**, not the load. A tripped breaker downstream still shows green. Wiring a digital input downstream of each circuit would close that gap — four inputs are free.

### Environnement page

One card per sensor, named as in VRM. A sensor silent for 15 min turns grey and dashed — a Ruuvi battery dying shows up before it's dead. The banner on top is the **barometer**: pressure and its 3-hour change. It turns orange at **−3 hPa/3 h** (a blow is coming) and red at **−5 hPa/3 h** (it's coming fast). Absolute pressure tells you little; the *rate* is the forecast.

---

## 9. Alerts — what fires and how to tune it

All thresholds live in `haku.env`. Defaults:

| Alert | Trigger | Variable |
|---|---|---|
| Low SOC | < 30 % | `ALERT_SOC_MIN` |
| Low voltage | < 24.8 V | `ALERT_VBAT_MIN` |
| No full charge | 14 days without reaching 28.4 V for 10 min | `FULLCHARGE_*` |
| Shore power lost | > 5 min | `ALERT_AC_LOSS_MIN` |
| Cerbo unreachable | > 15 min | `CERBO_TIMEOUT_MIN` |
| Strong wind | > 35 kn | `WIND_ALERT_KT` |
| SOC drift at dock | −5 pts in 48 h with dock-watch on | `SURV_SOC_*` |
| Engine room | > 60 °C (45 °C in dock-watch) | `TEMP_ALERT_RULES` |
| Freezer / fridge | > −10 °C / > 14 °C, **held 30 min** | `TEMP_ALERT_RULES`, `TEMP_ALERT_DELAY_MIN` |
| Pressure drop | −3 hPa/3 h watch, −5 alert | `BARO_DROP_WATCH`, `BARO_DROP_ALERT` |

Every alert has a **return-to-normal** message and a 24 h reminder (`ALERT_REMIND_H`). Temperature rules match on a fragment of the sensor's name, so renaming a sensor in VRM is all you need to re-target one.

Test the whole chain with the **"Tester l'alerte email"** button on the Bord page.

---

## 10. Test recipe — before you trust it

| # | Do | Expect |
|---|---|---|
| 1 | Unplug the Cerbo's Ethernet for 20 min | e-mail "Cerbo injoignable", then "de retour" |
| 2 | Instruments switch OFF then ON | relay clicks, dot ⚪ then 🟢 within 5 s |
| 3 | Spreader switch ON | lights on, dot 🟢 |
| 4 | `sudo systemctl restart nodered` | every relay re-asserted to its wanted state; NC circuits never blink |
| 5 | Cut the Waveshare's power for 6 min | e-mail "module injoignable", dots 🟠; NC circuits stay powered, NO circuits go off |
| 6 | Lift a bilge float by hand | tile turns to ALARM, e-mail within 5 s, panel buzzer still sounds |
| 7 | Press the test-alert button | one e-mail |
| 8 | At anchor at dusk, more than 3 NM from home | anchor light on ~30 min before sunset, off at sunrise |
| 9 | From the phone on 4G, Wi-Fi off | dashboard loads through Tailscale |
| 10 | Pull the Pi's power, wait, plug back | everything back within 2 min, no action needed |

---

## 11. Troubleshooting — the lessons we paid for

**The Cerbo disappears from the LAN.** It's on Wi-Fi and moved to a stronger network. Wire it (§3). Until then: Settings → Wi-Fi → *forget* the other network.

**Anchor light and logbook stopped after a Venus OS update.** Node-RED restarted in safe mode. `https://venus.local:1881` → Deploy.

**The Pi freezes every few weeks.** Under-voltage. `vcgencmd get_throttled` ≠ `0x0` → fix the power supply (§2.3).

**A dashboard switch works backwards.** `WAVESHARE_*_CONTACT` doesn't match what you wired. Change the variable, restart Node-RED. Don't touch the wires.

**The anchor light comes on at the home berth.** The home port isn't set on the Cerbo. Click "Définir le port ici" at the berth.

**"Waveshare injoignable" but the module's RJ45 LEDs are dark.** They're not link LEDs — see §6.1. Check RUN/STA blink, then the IP.

**A relay-link fuse blows when you transmit on the VHF.** You sized it on standby current. A 25 W VHF draws ~3 A on the 24 V side while transmitting. Use 6–7.5 A on that circuit.

**The status dots sit below the switches on your phone.** They shouldn't since v1.3 (dot is part of the switch label). If you customise the dashboard: below 576 px Dashboard 2.0 renders groups at **3 columns**; two side-by-side widgets will always wrap. One widget per row.

**"Aucune sonde reçue" on the Environnement page.** MQTT is down (Cerbo unreachable) or your sensors aren't declared on the Cerbo (Settings → Integrations).

---

## 12. Maintenance

- **Backups** run nightly to `/boot/firmware/haku-backup` (flows, journal, tracks, ports, `haku.env`). That's on the *same* SSD — copy that folder off the boat regularly (`scp -r bord@haku:/boot/firmware/haku-backup .`). A proper off-boat backup is on the roadmap.
- **Update:** `cd haku-pi && git pull && cd pi && sudo bash install.sh`.
- **Health:** `curl http://haku:1880/health` — a JSON with everything that matters; `flow_errors` must be 0.
- **Weekly reboot** is scheduled (Sunday 04:30) — a Pi left alone for months appreciates it.

---

## 13. Roadmap / not done yet

- A proper "force on / auto" channel from the Pi to the Cerbo's anchor-light flow.
- Digital inputs downstream of each switched circuit, so the status dots prove the *load* is powered, not just the relay.
- Off-boat backup (cloud), complete and permanent.
- Remote cold-restart of the Pi via a Cerbo relay — the only remedy that worked the day the Pi froze.
- Water and fuel tank levels.

---

*Questions, improvements, other boats: open an issue. If it saves you the weekends it cost us, it was worth publishing.*
