# KiCad Board Setup — Solitaire PCB

2-layer board, fabbed by JLCPCB (parts sourced via LCSC). Notes for
`Board Setup → Design Rules` and net classes.

## Design Rules → Constraints

| Setting | Value | Why |
|---|---|---|
| Minimum track width | 0.15mm (6mil) | JLCPCB economic min is 0.1mm; 0.15mm gives margin at no price bump |
| Minimum clearance | 0.15mm (6mil) | matches their standard tolerance |
| Minimum via diameter | 0.45mm | needs pad ≥ drill + 0.15mm each side for annular ring |
| Minimum via drill | 0.3mm | standard min drill (0.2mm possible but costs more / lower yield) |
| Min hole-to-hole | 0.5mm | avoids their spacing DRC flags |
| Copper-to-edge clearance | 0.3mm | JLCPCB wants ≥0.3mm from board outline |

## Net Classes

Don't leave everything on one Default class — split by current/noise sensitivity:

| Class | Track width | Via | Used for |
|---|---|---|---|
| Default/Signal | 0.2mm | 0.5mm | GPIO, SPI/I2C to display, buttons |
| Power | 0.4mm | 0.6mm | VBAT, VCC distribution |
| Regulator_SW | 0.5–0.6mm | 0.6mm | TPS63900 switch-node/inductor loop, in/out caps |

Rough IPC-2221 current capacity (1oz Cu, external layer, 10°C rise) for reference:
- 0.2mm (~8mil) ≈ 0.3A
- 0.4mm (~16mil) ≈ 0.7A
- 0.6mm (~24mil) ≈ 1A

This board's currents are all small (battery-powered handheld), so width is more about
noise/loop area than raw ampacity — except right at the regulator.

## 2-Layer-Specific Layout Advice

No internal ground plane on 2-layer, so:

- Pour copper fill tied to GND on **both** layers, and stitch them with vias every
  ~3–5mm around the board edge and near the regulator. This substitutes for a
  dedicated ground plane.
- Route the TPS63900's switch node and inductor loop as short/direct as possible —
  matters more than trace width here, since there's no plane underneath to absorb
  return current cleanly.
- Route any feedback/compensation traces near the regulator *before* pouring
  copper, and keep them away from the switch node — most noise-sensitive nets
  on the board.
- JLCPCB default is 1oz copper, HASL (or ENIG/LeadFree HASL if selected) —
  1oz is plenty for this board's current levels.

## Design Rule Severities

Most of these were already set to error/warning in the project file. Worth
double-checking, and bumping these two to error given the fine-pitch parts
(MSP430FR2355 DBT package, 0.5mm-pitch FPC connector):

- `silk_over_copper`
- `courtyards_overlap`
