# Wiring — relays, fuses and safety

*This is the electrical part. Read all of it before touching the panel. Everything below was built on a 24 V Amel 50; adapt fuse ratings to your loads.*

> ⚠️ **Work de-energised.** Trip the breaker of every circuit you touch, then confirm 0 V with a meter before cutting anything. Remove rings and watch. Photograph before, photograph after.

---

## 1. The principle: the relay goes *in series, after the breaker*

```
Panel breaker (DJ) ──► COM ──[ relay contact ]──► NO or NC ──► your circuit
```

- The original **breaker stays upstream** and remains the protection **and** the master switch: trip it, the circuit is dead whatever the relay does.
- **Never tap the panel's common +24 V input bus.** That bus is upstream of every breaker; a tap there is protected by nothing but the main fuse (often 100 A+). Cut into the circuit's *output* wire, after its breaker.
- One relay per circuit. One circuit per relay.

## 2. Terminals on the Waveshare (B)

Each channel has three screw terminals:

| Terminal | Function |
|---|---|
| **1** | **NC** — normally closed (conducts when the coil is *not* energised) |
| **2** | **COM** — common |
| **3** | **NO** — normally open (conducts when the coil *is* energised) |

Verify on your own unit with a meter in continuity mode, module unpowered: the pair that beeps is **COM + NC**.

## 3. NO or NC? Decide what "module dead" should mean

The contact choice is not cosmetic. It decides what happens when the module loses power, the Pi crashes, or the network drops. **Wire each circuit so that "module dead" gives its safe state.**

| Circuit | Safe state if the module dies | Contact to use |
|---|---|---|
| Navigation instruments, VHF | **powered** — you never want to lose the VHF at sea | **NC** |
| Spreader lights, deck lights | **off** — no light left burning, no battery drain | **NO** |
| Anything you must be able to cut remotely for safety | depends — think it through | — |

With NC the coil is energised only while the circuit is **off**; with NO it's energised while the circuit is **on**. Both are fine electrically; the software handles either — you just tell it which one you wired (`WAVESHARE_INSTR_CONTACT=NC|NO`, `WAVESHARE_LIGHT_CONTACT=NC|NO` in `haku.env`).

**On Haku we wired both on NO** by the owner's decision (no change to the original panel: the breaker remains the only manual control). Consequence, accepted and documented: if the module loses power, the instruments go off until someone intervenes. If you want the instruments to survive a module failure, use NC for that channel. Thirty seconds of wiring, one line in `haku.env`.

## 4. Fuses — what they protect and where

A fuse protects the **wire**, sized on its section and capped by the real load. It goes **as close as possible to the point where you take power** — the stretch between the tap and the fuse is protected by nothing.

| Wire section | Max fuse |
|---|---|
| 0.75 mm² | 5 A |
| 1.0 mm² | 7.5 A |
| **1.5 mm²** | **10 A** |
| 2.5 mm² | 15 A |

Take **1.5 to 2× the real current**, rounded up to a standard value, never above the wire's limit.

### Inline fuses on the relay links

Even though the panel breaker is upstream, add an inline fuse on each relay link, on the **COM** side, next to the breaker terminal. It protects two things the breaker doesn't: the **relay contact (10 A)** and your **1.5 mm² link** — a 15 A breaker would let 15 A through a 10 A contact.

| Circuit | Standby | Peak | Fuse |
|---|---|---|---|
| Instruments **+ VHF** | 1.2 A | **~4–5 A** while transmitting at 25 W | **6 A** (7.5 A if your meter says more) |
| Spreader lights (LED) | 1.2 A | 1.2 A | **3 A** |

> ⚠️ **Measure with the VHF transmitting**, not receiving. A 25 W VHF draws 5–6 A at 12 V on transmit — about 3 A on the 24 V side through the converter — versus a few hundred mA on standby. Size on standby and the fuse blows on your first Mayday.

### Supply fuses

| Device | Fuse | Where |
|---|---|---|
| Pi's DC-DC converter | **2 A** | on the 24 V input, at the tap |
| Waveshare | **3–5 A** | its own panel breaker (5 A ideal), or an inline fuse if tapped elsewhere |

Standard blade fuses, **not fast-acting** — switching power supplies have an inrush at start-up.

## 5. Connections

| Method | Verdict |
|---|---|
| **Crimped butt splice with adhesive-lined heat-shrink** | ✅ The right one. Mechanical hold from the crimp, seal from the glue. ABYC-compliant. Ratcheting crimper. |
| **Wago 221** lever connectors | 🟠 Acceptable **behind the panel, in the dry, fixed with a tie**, at these currents. Not in the bilge, not in the engine room. |
| **Solder-seal heat-shrink connectors** | ❌ No. The solder stiffens the strands; under vibration the copper fatigues and snaps right at the solder line, invisibly, inside the sleeve. |

Rules that apply whatever you use:
- **Never pre-tin a stranded wire** that goes into a screw or spring terminal. Tin creeps under pressure, the clamp loosens, it heats.
- **One wire per terminal.** Two wires that need the same point → a Wago or a splice, never two wires forced into one clamp.
- **Ferrule** on every stranded wire entering a screw terminal (Waveshare, converter).
- **Service loop** of ~10 cm and a cable tie within 5 cm of every terminal. Boats vibrate.
- **Label both ends** of every new wire with the original circuit number plus a suffix (`0804-COM`, `0804-NO`).

## 6. Worked example — Haku's two circuits

```
CH1 — Instruments (original wire 0901, breaker DJ6 15 A, 4 mm²)
   DJ6 terminal ──[6 A fuse]──► COM (terminal 2)
   0901 ◄─────────────────────── NO  (terminal 3)      ← NC (1) if you want fail-powered

CH2 — Spreader lights (original wire 0804, breaker DJ20 10 A, 1.5 mm²)
   DJ20 terminal ──[3 A fuse]──► COM (terminal 2)
   0804 ◄─────────────────────── NO  (terminal 3)
```

Steps, per circuit, breaker tripped:
1. Find the circuit's output wire at the panel terminal strip (the printed sleeve number).
2. Move it from its terminal to a **free** terminal on the strip (or into a Wago).
3. Run a new 1.5 mm² wire from the breaker's original terminal → inline fuse → **COM**.
4. Connect the circuit wire → **NO** (or NC).
5. Re-energise. **Functional check:** with the module unpowered, a NO circuit must be **off** and a NC circuit **on**. If it's the other way round you're on the wrong side terminal.

## 7. Powering the Waveshare

The module is a 7–36 V DC device. Give it **its own breaker or fuse (3–5 A)**, on a **permanent** circuit — one that stays on when the boat is left. Never feed it from a circuit it controls: tripping that breaker would kill the module that commands it.

On Haku: a spare 5 A breaker on the comfort panel. Label it **"SUPERVISION — DO NOT SWITCH OFF"**.

## 8. Digital inputs (bilge float switches)

The (B) module's inputs are opto-isolated and accept 5–30 V. Tap **in parallel** on the existing 24 V alarm loops — the panel's own buzzer and lamp keep working. Measure each loop at rest and with the float lifted **before** connecting, and set `WAVESHARE_DI_INVERT` accordingly (it is global: all loops must have the same logic).

Details in `docs/REFERENCE_FR.md` §Waveshare (French).

---

*This document describes what was done on one boat. It is not a substitute for a marine electrician's judgement on yours. If in doubt about a circuit — especially anything feeding the VHF, the bilge pumps or the navigation lights — ask one.*
