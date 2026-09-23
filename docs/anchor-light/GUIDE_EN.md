# Automatic Anchor Light via Victron Cerbo GX — Full DIY Guide (Amel)

*Turn your anchor (mooring) light on and off automatically — at dusk, only when anchored, only outside your home port — while keeping the original manual switch fully working. Built and tested on a 24 V Amel 50 ("Haku"). Any Amel owner with a Victron Cerbo GX can reproduce it alone.*

> **Copy kept for convenience.** The maintained version — v3.1, with a French guide, wiring diagrams and unit tests — lives at **https://github.com/SLPH77300/anchor-light-auto-cerbo-amel**. The flow in this repository (`cerbo/anchor-light-v3.1.flow.json`) is that v3.1: no default home port (light locked OFF until you set yours), relay re-asserted every 5 min, TEST injects. The code embedded at the end of this page is the older version, kept only as reference.

---

## 1. What it does

The Cerbo GX switches the anchor light through its built‑in **Relay 1**, driven by a small **Node‑RED** flow running on the Cerbo itself (no extra hardware, no cloud, no PC needed once set up).

**The light turns ON only when ALL three conditions are true:**
- **Night** — sun is below the horizon at the boat's GPS position (astronomical calc, no internet).
- **Away from home port** — more than a set radius (default 2 NM) from your home berth.
- **Stationary** — speed over ground below 1 knot (so it never comes on while sailing).

Otherwise the light is OFF. The check runs every 30 minutes and the relay is written **only when the state changes**.

The **manual switch keeps priority**: it is wired in parallel and works even if the Cerbo or Node‑RED is off.

---

## 2. Requirements

- **Victron Cerbo GX** (or any GX device with at least one relay) running **Venus OS Large** (Node‑RED is built in — free).
- A **GPS feeding the Cerbo** (NMEA 2000 GPS on the boat, or a Victron GPS). The flow reads Latitude, Longitude and Speed from it.
- An existing **anchor/mooring light on a switched circuit** to tap into (all Amels have this).
- Basic tools: crimper, multimeter, an in‑line fuse holder + 5 A fuse, a bit of 1.5 mm² tinned cable.

> LED anchor light assumed (a few watts). The Cerbo relay is a potential‑free contact rated **6 A max @ ≤ 30 VDC** — an LED light is far below this, so it switches it directly with no external relay.

---

## 3. Wiring (the electrical part)

**Key point: the Cerbo relay is a DRY (potential‑free) contact — it is just a switch. It does NOT output + or –.** You place it **in parallel with the existing anchor‑light switch**, so that **either the switch OR the relay** sends +24 V (or +12 V) to the light.

### Cerbo Relay 1 terminals
| Relay terminal | Connect to |
|---|---|
| **COM** | **Permanent + (24 V)** taken from the switch‑panel supply bus, **through a 5 A in‑line fuse** |
| **NO** | The **wire that runs from the anchor‑light switch to the light** (i.e. the switched output) |
| **NC** | Not used |

The light's **negative** goes straight to the boat's negative bus as before (never through the relay).

### On Haku (Amel 50), for reference
- Anchor light circuit **0702**, breaker **DJ2 5 A**, folio 07 ("Platine 24 VDC N°2 – Table à carte").
- Relay 1 **NO** connected to wire **0702** (switch output → light).
- Relay 1 **COM** connected to permanent **+24 V** on the switch‑input bus, via a **5 A in‑line fuse**.
- Cable: **1.5 mm² tinned marine**, ferrules crimped.
- The original green indicator lamp is wired on the output side (0702 → negative), so **it lights whether the switch or the relay turns the light on** — no change to the panel behaviour.

### Safety rules
- **In‑line fuse (5 A) within ~18 cm (7") of the + tap** (ABYC): the short piece of wire between the bus and the fuse is otherwise unprotected.
- Fuse holder **fixed** (cable‑tied), not dangling; use a **weatherproof** holder if in a locker/lazarette.
- No conflict if switch and relay are both on at once — same +24 V on the same wire.
- **Fail‑safe:** the relay uses the **NO** contact, so if the flow stops or the Cerbo reboots, the relay drops out and the light defaults to **OFF** (the manual switch still works).

---

## 4. Cerbo / software setup

### 4.1 Enable the tools
1. **Venus OS Large**: *Settings → Firmware → Online updates* → make sure you are on a **"large"** image (it contains Node‑RED + Signal K). If not, install the Large image.
2. **Enable Node‑RED**: *Settings → Services → Node‑RED → Enabled* (or "Enabled (with dashboard)").
3. **Set Relay 1 to Manual** so Node‑RED can control it: *Settings → Relay → Function (Relay 1) → **Manual***. (If it is left on "Alarm" or "Generator", external control is blocked.)

### 4.2 Import the flow
1. On a laptop/tablet on the same network, open **`http://venus.local:1880`** (or `http://<Cerbo‑IP>:1880`).
2. **Menu (☰) → Import**, paste the JSON from **Section 6** (or import the file `HAKU_NodeRED_FeuMouillage_v2.json`), then **Import**.
3. Click **Deploy** once.

### 4.3 Configure the 4 Victron nodes (do this AFTER the first Deploy)
Open each node, pick the Victron client, then select the source:
- **GPS Latitude** node → your GPS device, measurement **Latitude**.
- **GPS Longitude** node → your GPS device, measurement **Longitude**.
- **GPS Vitesse** node → your GPS device, measurement **Speed**.
- **Relais 1 (feu mouillage)** node → service `com.victronenergy.system`, path **`/Relay/0/State`**.

Then **Deploy** again.

### 4.4 Set your home port
Two options:
- **Easy:** while sitting at your home berth, click the inject button **"Definir le port ici (clic)"** → it captures the current GPS position as home port.
- **Manual:** edit the default in the function node **"charger port (defaut Termini)"** — replace `lat`, `lon`, `radius` (default `37.986 / 13.704 / 2` = Termini Imerese, 2 NM).

### 4.5 Optional tuning (in the "Decision" function node)
- `SUN = -0.833` → sunset/sunrise. Use `-6` for civil twilight (light comes on earlier).
- `RADIUS = 2` → home‑port radius in NM.
- `SPEED_MAX_KN = 1.0` → "stationary" threshold in knots.

### 4.6 Persistence (survives reboots)
The flow stores state in `/data/haku_homeport.json` and `/data/haku_lastpos.json`. The `/data` partition persists across reboots **and firmware updates**. At anchor the GPS is often powered down, so the flow keeps the **last known position** to keep deciding correctly.

---

## 5. Testing, safety & troubleshooting

**Force an ON test:** temporarily set `SPEED_MAX_KN = 99`, `RADIUS = 0`, `SUN = 90` in the Decision node → Deploy → the relay and light should switch ON within a few seconds. Restore the values afterwards.

**Legal (COLREG Rule 30):** a vessel at anchor must exhibit an all‑round white anchor light. The **"stationary < 1 kn"** condition guarantees the light **never** comes on while underway (you show your normal navigation lights instead). The **manual switch always overrides** — treat the automation as an aid, not a replacement, and check local requirements. Choose a home‑port radius that does not overlap anchorages where you regularly stop.

**Troubleshooting (watch each node's status text):**
- `aucune position connue` → GPS nodes not configured, or no GPS fix yet.
- Relay never switches → Relay 1 is not set to **Manual**, or the relay node path isn't `/Relay/0/State`.
- Light stays on at the dock → your berth is inside the home‑port radius? Check the captured home position.

---

## 6. Full Node‑RED code (import this)

> Node‑RED → Menu → Import → paste everything below → Import → Deploy. Then configure the 4 Victron nodes (Section 4.3).

```json
[
  { "id": "tab2", "type": "tab", "label": "HAKU - Feu mouillage auto v2", "disabled": false, "info": "" },
  { "id": "vc2", "type": "victron-client", "name": "" },
  {
    "id": "clock", "type": "inject", "z": "tab2", "name": "Horloge 30 min",
    "props": [ { "p": "payload" } ], "repeat": "1800", "crontab": "", "once": true, "onceDelay": "8",
    "topic": "", "payload": "", "payloadType": "date", "x": 170, "y": 120, "wires": [ [ "decide" ] ]
  },
  {
    "id": "decide", "type": "function", "z": "tab2", "name": "Decision (nuit+hors port+immobile)",
    "func": "var rad=Math.PI/180,dayMs=86400000,J1970=2440588,J2000=2451545,e=rad*23.4397;\nfunction toDays(d){return d.valueOf()/dayMs-0.5+J1970-J2000;}\nfunction sma(d){return rad*(357.5291+0.98560028*d);}\nfunction ecl(M){var C=rad*(1.9148*Math.sin(M)+0.02*Math.sin(2*M)+0.0003*Math.sin(3*M));return M+C+rad*102.9372+Math.PI;}\nfunction dec(l){return Math.asin(Math.sin(e)*Math.sin(l));}\nfunction ra(l){return Math.atan2(Math.sin(l)*Math.cos(e),Math.cos(l));}\nfunction sid(d,lw){return rad*(280.16+360.9856235*d)-lw;}\nfunction sunAlt(dt,la,ln){var lw=rad*-ln,phi=rad*la,d=toDays(dt),M=sma(d),L=ecl(M),de=dec(L),r=ra(L),H=sid(d,lw)-r;return Math.asin(Math.sin(phi)*Math.sin(de)+Math.cos(phi)*Math.cos(de)*Math.cos(H))/rad;}\nfunction distNM(a,b,c,d){var R=3440.065,p=Math.PI/180,x=(c-a)*p,y=(d-b)*p;var s=Math.sin(x/2)*Math.sin(x/2)+Math.cos(a*p)*Math.cos(c*p)*Math.sin(y/2)*Math.sin(y/2);return 2*R*Math.asin(Math.sqrt(s));}\nvar liveLat=global.get('gpsLat'),liveLon=global.get('gpsLon'),sog=global.get('gpsSpeed');\nvar lat,lon,fresh=false;\nif(typeof liveLat==='number'&&typeof liveLon==='number'){lat=liveLat;lon=liveLon;fresh=true;global.set('lastPos',{lat:lat,lon:lon});}\nelse{var lp=global.get('lastPos');if(lp&&typeof lp.lat==='number'){lat=lp.lat;lon=lp.lon;}}\nif(typeof lat!=='number'){node.status({fill:'grey',shape:'ring',text:'aucune position connue'});return null;}\nvar home=global.get('homePort')||null;\nvar RADIUS=(home&&typeof home.radius==='number')?home.radius:2;\nvar SUN=-0.833, SPEED_MAX_KN=1.0;\nvar night=sunAlt(new Date(),lat,lon)<SUN;\nvar away=true; if(home&&typeof home.lat==='number'){away=distNM(lat,lon,home.lat,home.lon)>RADIUS;}\nvar kn=(typeof sog==='number')?sog/0.514444:0;\nvar moving=kn>SPEED_MAX_KN;\nvar wantOn=night&&away&&!moving;\nvar persistMsg=fresh?{payload:JSON.stringify({lat:lat,lon:lon})}:null;\nvar tag=(fresh?'live':'last')+' '+kn.toFixed(1)+'kn';\nvar last=context.get('lastState');\nif(wantOn===last){node.status({fill:wantOn?'yellow':'blue',shape:'dot',text:(wantOn?'ON':'OFF')+' '+tag});return [null,persistMsg];}\ncontext.set('lastState',wantOn);\nnode.status({fill:wantOn?'green':'blue',shape:'dot',text:(wantOn?'ON mouillage':'OFF')+' '+tag});\nreturn [{payload:wantOn?1:0},persistMsg];",
    "outputs": 2, "noerr": 0, "initialize": "", "finalize": "", "libs": [],
    "x": 440, "y": 120, "wires": [ [ "relay" ], [ "fo_last" ] ]
  },
  {
    "id": "relay", "type": "victron-output-relay", "z": "tab2", "client": "vc2",
    "service": "com.victronenergy.system", "path": "/Relay/0/State", "serviceObj": {}, "pathObj": {},
    "initialValue": "", "onlyChanges": false, "name": "Relais 1 (feu mouillage)", "x": 760, "y": 110, "wires": []
  },
  {
    "id": "fo_last", "type": "file", "z": "tab2", "name": "ecrire lastPos",
    "filename": "/data/haku_lastpos.json", "filenameType": "str", "appendNewline": false,
    "createDir": true, "overwriteFile": "true", "encoding": "utf8", "x": 760, "y": 150, "wires": [ [] ]
  },
  {
    "id": "g_lat", "type": "victron-input-gps", "z": "tab2", "client": "vc2", "service": "", "path": "",
    "serviceObj": {}, "pathObj": {}, "initialValue": "", "onlyChanges": true,
    "name": "GPS Latitude -> a config (Latitude)", "x": 200, "y": 220, "wires": [ [ "s_lat" ] ]
  },
  {
    "id": "s_lat", "type": "function", "z": "tab2", "name": "store lat",
    "func": "var v=(msg.payload&&msg.payload.value!==undefined)?msg.payload.value:msg.payload;var n=Number(v);if(!isNaN(n))global.set('gpsLat',n);return null;",
    "outputs": 1, "noerr": 0, "libs": [], "x": 480, "y": 220, "wires": [ [] ]
  },
  {
    "id": "g_lon", "type": "victron-input-gps", "z": "tab2", "client": "vc2", "service": "", "path": "",
    "serviceObj": {}, "pathObj": {}, "initialValue": "", "onlyChanges": true,
    "name": "GPS Longitude -> a config (Longitude)", "x": 205, "y": 265, "wires": [ [ "s_lon" ] ]
  },
  {
    "id": "s_lon", "type": "function", "z": "tab2", "name": "store lon",
    "func": "var v=(msg.payload&&msg.payload.value!==undefined)?msg.payload.value:msg.payload;var n=Number(v);if(!isNaN(n))global.set('gpsLon',n);return null;",
    "outputs": 1, "noerr": 0, "libs": [], "x": 480, "y": 265, "wires": [ [] ]
  },
  {
    "id": "g_spd", "type": "victron-input-gps", "z": "tab2", "client": "vc2", "service": "", "path": "",
    "serviceObj": {}, "pathObj": {}, "initialValue": "", "onlyChanges": true,
    "name": "GPS Vitesse -> a config (Speed)", "x": 195, "y": 310, "wires": [ [ "s_spd" ] ]
  },
  {
    "id": "s_spd", "type": "function", "z": "tab2", "name": "store speed",
    "func": "var v=(msg.payload&&msg.payload.value!==undefined)?msg.payload.value:msg.payload;var n=Number(v);if(!isNaN(n))global.set('gpsSpeed',n);return null;",
    "outputs": 1, "noerr": 0, "libs": [], "x": 485, "y": 310, "wires": [ [] ]
  },
  {
    "id": "inj_set", "type": "inject", "z": "tab2", "name": "Definir le port ici (clic)",
    "props": [ { "p": "payload" } ], "repeat": "", "crontab": "", "once": false, "onceDelay": 0.1,
    "topic": "", "payload": "", "payloadType": "date", "x": 200, "y": 400, "wires": [ [ "fn_cap" ] ]
  },
  {
    "id": "fn_cap", "type": "function", "z": "tab2", "name": "Capturer port = position",
    "func": "var lat,lon;\nif(msg.payload&&typeof msg.payload==='object'&&typeof msg.payload.lat==='number'){lat=msg.payload.lat;lon=msg.payload.lon;}\nelse{lat=global.get('gpsLat');lon=global.get('gpsLon');}\nif(typeof lat!=='number'||typeof lon!=='number'){node.status({fill:'red',shape:'ring',text:'coords manquantes'});return null;}\nvar ex=global.get('homePort')||{};\nvar home={lat:lat,lon:lon,radius:(typeof ex.radius==='number'?ex.radius:2)};\nglobal.set('homePort',home);\nnode.status({fill:'green',shape:'dot',text:'port: '+lat.toFixed(4)+', '+lon.toFixed(4)});\nmsg.payload=JSON.stringify(home);return msg;",
    "outputs": 1, "noerr": 0, "libs": [], "x": 470, "y": 400, "wires": [ [ "fo_port" ] ]
  },
  {
    "id": "fo_port", "type": "file", "z": "tab2", "name": "ecrire port",
    "filename": "/data/haku_homeport.json", "filenameType": "str", "appendNewline": false,
    "createDir": true, "overwriteFile": "true", "encoding": "utf8", "x": 710, "y": 400, "wires": [ [] ]
  },
  {
    "id": "inj_st", "type": "inject", "z": "tab2", "name": "Au demarrage",
    "props": [ { "p": "payload" } ], "repeat": "", "crontab": "", "once": true, "onceDelay": "2",
    "topic": "", "payload": "", "payloadType": "date", "x": 180, "y": 480, "wires": [ [ "fi_port", "fi_last" ] ]
  },
  {
    "id": "fi_port", "type": "file in", "z": "tab2", "name": "lire port",
    "filename": "/data/haku_homeport.json", "filenameType": "str", "format": "utf8", "chunk": false,
    "sendError": false, "encoding": "utf8", "allProps": false, "x": 400, "y": 470, "wires": [ [ "fn_lport" ] ]
  },
  {
    "id": "fn_lport", "type": "function", "z": "tab2", "name": "charger port (defaut Termini)",
    "func": "try{var h=JSON.parse(msg.payload);if(h&&typeof h.lat==='number'){global.set('homePort',h);node.status({fill:'green',shape:'dot',text:'port charge'});return null;}}catch(e){}\nglobal.set('homePort',{lat:37.986,lon:13.704,radius:2});\nnode.status({fill:'blue',shape:'dot',text:'port defaut: Termini Imerese'});return null;",
    "outputs": 1, "noerr": 0, "libs": [], "x": 650, "y": 470, "wires": [ [] ]
  },
  {
    "id": "fi_last", "type": "file in", "z": "tab2", "name": "lire lastPos",
    "filename": "/data/haku_lastpos.json", "filenameType": "str", "format": "utf8", "chunk": false,
    "sendError": false, "encoding": "utf8", "allProps": false, "x": 405, "y": 515, "wires": [ [ "fn_llast" ] ]
  },
  {
    "id": "fn_llast", "type": "function", "z": "tab2", "name": "charger lastPos",
    "func": "try{var p=JSON.parse(msg.payload);if(p&&typeof p.lat==='number'){global.set('lastPos',p);node.status({fill:'green',shape:'dot',text:'lastPos charge'});}}catch(e){node.status({fill:'grey',shape:'ring',text:'pas de lastPos'});}return null;",
    "outputs": 1, "noerr": 0, "libs": [], "x": 650, "y": 515, "wires": [ [] ]
  }
]
```

---

*Node names are in French in the flow but the logic is universal — rename them freely. Built and tested on "Haku", Amel 50, 24 V, Cerbo GX + Venus OS Large. Use at your own risk; the manual switch and COLREG obligations always take precedence.*
