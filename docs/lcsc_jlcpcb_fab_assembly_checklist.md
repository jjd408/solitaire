# Fab + Assembly Checklist (JLCPCB/LCSC)

Status as of 2026-07-22 (commit `295d532`): DRC clean (0 violations, 0 unconnected items), GND zone on B.Cu actually filled (it existed since 2026-07-20 but sat unfilled through the J1 connector revert/redo until this session). Design rules (0.15mm/0.15mm track/space, 0.45mm min via) are within JLCPCB's standard 2-layer capability. No LCSC/MPN part numbers are in the schematic yet — that's the biggest open gap.

## Fab outputs (PCB)
- Gerbers (all copper/mask/silk layers) + Excellon drill files (PTH/NPTH split) — `File → Fabrication Outputs` in Pcbnew, or `kicad-cli pcb export gerbers` / `export drill`
- Confirm zones are filled before export (stale/unfilled fills silently ship wrong copper)
- Board thickness/layer stack — confirm 1.6mm 2-layer default is what's wanted (JLCPCB's cheapest tier)

## Assembly outputs (PCBA)
- **BOM with LCSC part numbers** — every part needs an LCSC `C123456`-style number in a field (add an "LCSC" or "MPN" property per symbol in the schematic). Not done yet.
- **CPL / placement file** — refdes, X/Y, rotation, side (top/bottom) for every SMD part. `kicad-cli pcb export pos` generates this; rotations often need hand-correction against JLCPCB's per-part rotation convention (check each part in their upload preview before ordering).
- Decide **Basic vs Extended** parts — Basic parts have no setup fee; Extended parts add a one-time fee per part number. Check if MSP430 / TPS63900-class coil / tact switches have Basic-library equivalents.
- THT parts (connectors, battery holder) — JLCPCB assembles thru-hole too but usually only on one pass/side and costs more; confirm placement side matches what they support.

## DFM sanity pass
- Silkscreen refdes not overlapping pads/each other (render silkscreen-only SVG to check)
- Polarity/pin-1 marks present for connectors and any polarized parts
- Mounting holes / board outline finalized, no stray copper past Edge.Cuts
- Copper-to-edge clearance is currently 0.3mm — right at JLCPCB's typical minimum, worth double-checking near J1–J4 by the board edge

## Before ordering
- Full DRC + ERC clean (DRC clean as of commit `295d532`; ERC has a stable 32-warning baseline, all expected "unspecified pintype" nags from imported connector symbols, no genuine errors)
- One more full render/visual pass now that routing is complete
