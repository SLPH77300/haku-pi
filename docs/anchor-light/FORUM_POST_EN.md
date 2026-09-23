# Amel group post — Automatic anchor light with the Cerbo GX

**Automatic anchor (mooring) light using the Victron Cerbo GX — no extra hardware**

I set up my anchor light on "Haku" (Amel 50) to switch itself on and off automatically, and I'm happy to share the full recipe (wiring + code) so anyone can copy it.

**What it does**
- Turns the anchor light **ON automatically at night, but only when the boat is actually anchored** — and **OFF** the rest of the time.
- Three conditions must all be true for it to light: **it's dark** (sun below horizon, calculated on board — no internet), **you're away from your home port** (default radius 2 NM), and **you're stationary** (< 1 knot).
- The **original manual switch still works normally** and always takes priority — the automation is just a parallel helper.

**How it's built**
- Runs entirely on the **Cerbo GX** with **Venus OS Large** (built‑in **Node‑RED**) — **no extra box, no cloud, no subscription**.
- The Cerbo's **Relay 1** switches the light; a small Node‑RED flow makes the decision.
- Position and speed come from the boat's **GPS via the Cerbo** (NMEA 2000).
- Checks every **30 minutes**, writes the relay **only when the state changes**.

**Wiring (simple)**
- The Cerbo relay is a **dry contact** (just a switch, no +/–). Wire it **in parallel with the existing anchor‑light switch**: **COM ← permanent + through a 5 A in‑line fuse**, **NO → the switch‑to‑light wire**, NC unused. Negative unchanged.
- On the Amel 50 that's circuit **0702** (breaker DJ2, 5 A). Cable **1.5 mm² tinned**, fuse within ~18 cm of the tap.
- The panel's green indicator still lights whether the switch or the relay turns it on.

**Safety / legal**
- **Fail‑safe OFF**: uses the NO contact, so if the Cerbo reboots or the flow stops, the light simply goes off and the manual switch still works.
- The **"stationary < 1 kn"** rule means it **never** comes on while underway (COLREG Rule 30 — you show your nav lights when moving). Treat it as an aid, keep the manual switch as master, and set a home‑port radius that doesn't cover anchorages you use.

**Setup, in short**
1. Venus OS **Large** + enable **Node‑RED**; set **Relay 1 → Manual**.
2. Import the flow, deploy, then point the 4 Victron nodes at your **GPS (lat/lon/speed)** and **Relay 1** (`/Relay/0/State`).
3. Set your **home port** (one click while at your berth) and, if you like, tweak radius / dusk angle / speed threshold.
4. Home‑port position survives reboots; at anchor (GPS off) it uses the **last known position**.

**Cost: basically zero** — a fuse, a fuse holder and a bit of wire; everything else is already in the Victron system.

Happy to share the **complete step‑by‑step guide with the full Node‑RED code and wiring diagram** — just ask and I'll send the file. Fair winds! ⚓
