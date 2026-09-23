# Haku Pi — open-source boat supervision on a Raspberry Pi + Victron Cerbo GX

*Remote dashboard, e-mail alerts, remote switching of instruments and lights, bilge alarms, environment sensors with a barometer, an automatic COLREG anchor light and a passage track recorder. Built and sailed on a 24 V Amel 50. Reproducible by any owner with a Cerbo GX.*

**🇫🇷 Version française : [docs/TUTORIEL_FR.md](docs/TUTORIEL_FR.md)** · **🇬🇧 Full tutorial: [docs/TUTORIAL_EN.md](docs/TUTORIAL_EN.md)**

---

## What it does

| | |
|---|---|
| **See the boat from anywhere** | battery, solar, shore power, wind, depth, position — on your phone, through Starlink or 4G, no port forwarding (Tailscale) |
| **Switch things remotely** | navigation instruments, spreader lights — with a **live status dot** that reads the relay back, so a command that didn't take shows red |
| **Get told when something's wrong** | low SOC, no shore power, water in a bilge, strong wind, fridge warming up, engine room too hot, **pressure dropping fast** — by e-mail, with return-to-normal and a daily reminder |
| **Anchor light on its own** | on 30 min before sunset, only when anchored and away from home port, off at sunrise — runs **on the Cerbo**, works with the Pi off. Standalone repo: [anchor-light-auto-cerbo-amel](https://github.com/SLPH77300/anchor-light-auto-cerbo-amel) |
| **Every passage on a map** | tracks recorded automatically from Signal K, a Leaflet map of all of them |
| **A barometer you didn't know you had** | Ruuvi sensors publish pressure; the dashboard shows a 3-hour trend and warns of a blow |
| **Built for an unattended boat** | hardware watchdog, logs in RAM, weekly reboot, dead-man heartbeat, self-recovery after a power cut |

## What it costs

~250–350 € — a Pi 4, an SSD, a **Waveshare Modbus POE ETH Relay (B)**, a proper DC-DC power supply, a small switch and some marine wire. Full list with links and the traps to avoid: **[docs/HARDWARE.md](docs/HARDWARE.md)**.

## What's in this repository

```
pi/            the Raspberry Pi package — run `sudo ./install.sh`
  install.sh   idempotent installer (Node-RED, Dashboard 2.0, InfluxDB, Grafana, hardening)
  node-red/    flows.json — the whole application
  config/      haku.env.example — every setting, commented
  scripts/     alerts, backup, healthcheck, heartbeat, track index…
cerbo/         flows for the Cerbo's own Node-RED
  anchor-light-v3.1.flow.json automatic anchor light — canonical repo: https://github.com/SLPH77300/anchor-light-auto-cerbo-amel
  logbook-v1.flow.json        daily logbook to a Google Sheet
docs/
  TUTORIAL_EN.md / TUTORIEL_FR.md   step by step, from bare Pi to tested system
  HARDWARE.md                       shopping list, links, voltage traps
  WIRING.md                         relays, NO vs NC, fuses, connectors, safety
  anchor-light/                     the original standalone anchor-light guide
  REFERENCE_FR.md, ARCHITECTURE_FR.md   in-depth reference (French)
```

## Quick start

```bash
# on a Raspberry Pi 4, Raspberry Pi OS Lite 64-bit, booted from SSD
git clone https://github.com/SLPH77300/haku-pi.git
cd haku-pi/pi
sudo ./install.sh
sudo nano /etc/haku/haku.env        # Cerbo IP, SMTP, Tailscale key…
sudo ./install.sh                   # apply
```

Then open `http://<pi>:1880/dashboard/haku`. The tutorial takes it from there — network, Cerbo settings, relay module, wiring, anchor light, tests.

## Design rule

**The Pi is the screen and the messenger, never the only safety.** The anchor light, the instruments and the bilge buzzer all keep working with the Pi dead. The Pi *adds* visibility and remote control; it never *replaces* the boat's original controls. Every relay is wired in series after its breaker, and each circuit is wired so that "module dead" gives the safe state for that circuit (see [WIRING.md](docs/WIRING.md)).

## Lessons we paid for (so you don't)

- **Wire the Cerbo, don't Wi-Fi it.** Venus OS picks the strongest known network and never comes back.
- **Power the Pi properly.** A boat USB socket gives you `throttled=0x50005` and a Pi that freezes every few weeks.
- **One master per relay.** Two programs writing the same relay silently switched our anchor light off at anchor.
- **Size fuses on the VHF transmitting**, not receiving — 3 A vs 4–5 A.
- **No solder-seal connectors on a boat.** They fatigue and break inside the sleeve.
- **After a Venus OS update, check Node-RED isn't in safe mode.** Ours was, for days.
- **Below 576 px, Dashboard 2.0 gives you 3 columns.** One widget per row, or it wraps.

## Status

v1.3.0 — in daily use on one boat since August 2026. Roadmap in the tutorial §13. Contributions, questions and reports from other boats: open an issue.

## Licence

MIT. Do what you want with it, keep the notice, don't blame us if your bilge fills up — **you remain responsible for your boat's electrical safety.** When in doubt about a circuit, ask a marine electrician.
