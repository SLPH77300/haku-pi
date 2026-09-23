# Changelog

## 1.3.0 — 2026-09-20
- Waveshare relays: NO/NC contact declared per channel (`WAVESHARE_*_CONTACT`); commands and readback follow the physical wiring.
- Commands block: live status dot embedded in each switch label (independent readback: Modbus FC01 / MQTT), single widget per row — renders on phones.
- Anchor light: the Pi no longer writes the Cerbo relay. The Cerbo flow (v3.1) is the single master; the Pi displays the relay's real state.
- New "Environnement" page: every Victron/Ruuvi temperature sensor (temperature, humidity, pressure, battery), barometer banner with 3-hour trend.
- New alerts: per-sensor temperature thresholds (held 30 min, 2 °C hysteresis, tighter engine-room threshold in dock-watch mode) and pressure-drop warnings (−3 / −5 hPa per 3 h).
- Labels made consistent across pages; bilge zone names aligned between dashboard tiles and alert e-mails.
- Surveillance page reordered: Battery · Commands · Wind · Link · Bilge alarms.

## 1.2.0 — 2026-08-30
- InfluxDB 2 + Grafana (long history), Waveshare Modbus TCP module (relays + digital inputs), spreader lights, healthchecks.io heartbeat, dock-watch SOC drift alert, strong-wind alert.

## 1.1.x — 2026-08
- Track recorder (Signal K → GPX + map), declared ports, geofence, daily CSV journal, Tailscale remote access, kiosk mode.

## 1.0 — 2026-08
- First version: MQTT link to the Cerbo, dashboard, e-mail alerts, anchor-light lock, unattended-boat hardening.
