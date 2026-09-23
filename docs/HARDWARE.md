# Hardware — shopping list

*What you need to reproduce the Haku Pi setup, with links. Prices are not quoted on purpose: they change. Check each listing's specifications yourself before ordering — during this project we found listings that contradicted themselves on the input-voltage range.*

> **Read this first.** A 24 V boat with a LiFePO4 bank sees **up to ~28.4 V during absorption**, and a 12 V boat sees ~14.6 V. Anything you power from the house bank must accept that with margin. **Reject any converter rated "max 28 V".** Look for **8–32 V** or wider.

---

## 1. The brain — Raspberry Pi

| Item | Notes | Link |
|---|---|---|
| **Raspberry Pi 4 Model B, 4 GB** | 2 GB works; 4 GB is comfortable with InfluxDB + Grafana. A Pi 5 also works but draws more current. | [Amazon.fr](https://www.amazon.fr/Raspberry-Pi-4595-mod%C3%A8les-Go/dp/B09TTNF8BT) |
| **2.5" SATA SSD, 120–240 GB** | Boot from SSD, not microSD: a card dies within months under continuous logging. A cheap SATA SSD is enough and draws less power than NVMe — that matters, see §2. | [Kingston A400 240 GB](https://www.amazon.fr/Kingston-SSD-A400-240GB-Disque-SATA/dp/B01N5IB20Q) |
| **USB 3.0 enclosure for the SSD** | Must support UASP. Some USB-SATA bridges misbehave on the Pi 4; the ORICO/JMS578 family is well known to work. | [ORICO 2.5" USB 3.0](https://www.amazon.fr/ORICO-Bo%C3%AEtier-Externe-pour-Disque/dp/B07F376TCG) |
| **microSD card, 16 GB** | Only for the first boot and for `rpi-clone` to the SSD. Any brand. | — |
| **Passive case with heatsink** | The Pi lives in a closed locker: give it a metal or well-vented case. No fan (dust, noise, one more thing to fail). | — |

---

## 2. Powering the Pi — the part everyone gets wrong

A Pi 4 with an SSD needs **5.1 V / 3 A**. A USB socket on the boat's panel gives 2.4 A at best, through a long thin cable. The result is a Pi that **freezes silently** every few weeks, and `vcgencmd get_throttled` returns `0x50005` (under-voltage *and* throttling, right now). We lived it.

**Rules:**
- **Dedicated DC-DC converter**, not a shared USB socket.
- **Input range 8–32 V minimum** (see the warning at the top).
- **Output 5.1 V if adjustable**, never below 5.0 V. The official Pi PSU outputs 5.1 V precisely to compensate cable drop.
- **3 A minimum, 5 A preferred.**
- **Short, thick USB-C cable** (≤ 1 m, 20 AWG power conductors, "5 A / 100 W" rated).

| Option | Notes | Link |
|---|---|---|
| **8–32 V → 5 V USB-C, 3 A, IP68** — simplest | Native USB-C, potted, protected. ⚠️ The listing states both "8–23 V" and "8–32 V": confirm with the seller before buying. 3 A is the minimum, no margin. | [Amazon.fr](https://www.amazon.fr/Convertisseur-Adaptateur-Alimentation-Interface-Abaisseur/dp/B0FHGVT1Y6) |
| **8–40 V → 5 V, 5 A, aluminium** — more margin | Bare-wire output: crimp a USB-C plug or use a quality USB-C cable with pigtails. Recommended. | [DEWIN](https://www.amazon.fr/Convertisseur-abaisseur-12V-module-dalimentation/dp/B07L5L9Z2J) |
| **8–60 V → 5 V, 5 A** | Same idea, wider input. | [Amazon.fr](https://www.amazon.fr/Convertisseur-Abaisseur-DC-DC-Module-dAlimentation/dp/B07N7969ZY) |

Fuse the converter's 24 V input at **2 A** (blade fuse, waterproof inline holder — see §5), as close to the tap point as possible.

---

## 3. The relay/input module — Waveshare

| Item | Notes | Link |
|---|---|---|
| **Waveshare Modbus POE ETH Relay (B)** | 8 relays (10 A / 30 V DC each, changeover NO-COM-NC) + **8 opto-isolated digital inputs**. Ethernet, Modbus TCP. Powered 7–36 V DC from the boat — PoE not needed. **Make sure it's the "(B)" version**: the plain "Modbus POE ETH Relay" has **no digital inputs**. | [Amazon.fr — (B) version](https://www.amazon.fr/Waveshare-Communication-Protection-Industrial-Rail-Mount/dp/B0D9W2YW9P) · [Official wiki](https://www.waveshare.com/wiki/Modbus_POE_ETH_Relay_(B)) |

What the relays are used for on Haku: **CH1 = navigation instruments (incl. VHF)**, **CH2 = spreader lights**. The 8 inputs are for the bilge float switches. Six relays and four inputs remain free.

Fuse its 24 V supply at **3–5 A**, ideally on its own breaker on the panel.

---

## 4. Network

| Item | Notes | Link |
|---|---|---|
| **5-port Gigabit switch** | The Pi, the Waveshare and the Cerbo GX must be on the **same wired LAN**. Most boat routers have one or two LAN ports — not enough. ⚠️ Check the switch's power adapter voltage: pick one you can feed from a 5 V or 12 V DC-DC, or an industrial 12–48 V DIN-rail model. | [TP-Link LS105G](https://www.amazon.fr/TP-Link-LS105G-Ethernet-metallique-2000Mbps/dp/B07RPVQY62) |
| **RJ45 cables, Cat 5e/6, 0.5–2 m** | Three: Pi, Waveshare, Cerbo. | — |

**Why wire the Cerbo instead of Wi-Fi:** Venus OS has **no Wi-Fi priority setting** — it connects to the strongest known network and does not come back. If your boat has a second Wi-Fi (Starlink, a 4G router…), the Cerbo will wander onto it and disappear from your LAN. **Ethernet always takes priority** over Wi-Fi on a GX device: wire it and the problem is gone.

---

## 5. Electrical small parts

| Item | Notes | Link |
|---|---|---|
| **Tinned marine wire, 1.5 mm²** (16 AWG) | For the relay links. **Tinned** — plain automotive wire corrodes. Buy from a marine chandlery; "marine" wire on general marketplaces is often not tinned. | chandlery |
| **Wago 221-413 lever connectors** (3-way, 0.2–4 mm²) | For splices **behind the panel, in the dry**. Not for the bilge. | [Amazon.fr, box of 50](https://www.amazon.fr/221-413-connexion-commande-transparent-compact/dp/B00JB3U9CG) |
| **Waterproof inline ATO/ATC blade fuse holders** | One per circuit you tap. | [Amazon.fr](https://www.amazon.fr/G%C3%A9n%C3%A9rique-Porte-fusible-%C3%A9tanche-ATO-ATC/dp/B0BDWF2LXV) |
| **Blade fuses** 2 A, 3 A, 5 A, 6 A, 7.5 A | See [WIRING.md](WIRING.md) for which goes where. | — |
| **Insulated wire ferrules, 1.5 mm²** + ratcheting crimper | For every wire that enters a screw terminal (Waveshare, converter). | — |
| **Cable ties, labels, heat-shrink** | Every wire gets a label at both ends. Future-you will thank you. | — |

**Do not buy solder-seal heat-shrink connectors** (the ones with a shiny solder ring in the middle). Solder makes stranded wire rigid; under vibration it fatigues and breaks at the edge of the solder, hidden inside the sleeve. ABYC E-11: solder must never be the sole mechanical connection.

---

## 6. Optional

| Item | Notes | Link |
|---|---|---|
| **Ruuvi Tag** temperature/humidity/pressure sensors | Bluetooth sensors read natively by the Cerbo GX (Venus OS ≥ 2.90). Engine room, fridge, freezer, cabins. **They also give you a barometer.** | [ruuvi.com](https://ruuvi.com) |
| **Healthchecks.io** account (free) | Dead-man heartbeat: you get an e-mail when the Pi *stops* reporting. | [healthchecks.io](https://healthchecks.io) |
| **Tailscale** account (free) | Reach the dashboard from anywhere, through Starlink/4G CGNAT, no port forwarding. | [tailscale.com](https://tailscale.com) |
| **HDMI screen** | Only if you want a kiosk display at the chart table. | — |

---

## Already on board (assumed)

- **Victron Cerbo GX** (or any GX device) running **Venus OS Large** — Node-RED and Signal K are built in.
- **Victron SmartShunt / BMV** for SOC.
- A **GPS** feeding the Cerbo (NMEA 2000 or Victron GPS) — needed for the anchor light and the track recorder.
- A **router with a LAN port** (Peplink/Pepwave, Teltonika, MikroTik, a 4G box… anything).
