# Case Design Dimensions

Pulled from the current PCB (`hw/solitaire/solitaire.kicad_pcb`, commit `1d405bf`) and the datasheets in this `docs/` folder. Anything I couldn't verify from a real source is marked **TBD** rather than guessed — don't use unverified numbers for a case cutout.

All coordinates below are **relative to the board's bottom-left corner** (i.e. the board's own min-X/min-Y edge = (0,0)), not KiCad's internal sheet coordinates.

## Board

- **Outline**: 100.0 mm × 60.0 mm rectangle (simple rect, no cutouts/notches yet)
- **Thickness**: 1.6 mm (KiCad default — no custom stackup is defined in the project, so confirm this is actually what you want before fab)
- **Mounting holes**: 4× `MountingHole_2.7mm_M2.5` (2.7mm NPTH, no copper) added 2026-07-22, sized for M2.5 self-tapping screws into FDM case bosses. Positions (board-relative, same frame as the component table below):

  | Ref | X (mm) | Y (mm) | Notes |
  |---|---|---|---|
  | H1 | 86.53 | 7.53 | Top-right corner area — fully clear region, no component nearby. |
  | H2 | 86.53 | 52.53 | Bottom-right corner area — same clear region as H1. |
  | H3 | 6.53 | 20.53 | Substitutes for top-left — the true corner is blocked by J3 (SBW header, flush with the left edge) and U2 (MCU); shifted into the clear pocket between U2's bottom edge and J4. |
  | H4 | 20.53 | 53.53 | Substitutes for bottom-left — the true corner is blocked by the L1/U1/C1/C2/R1/R2 cluster; shifted right into the gap between R2 and SW2. |

  H3/H4 aren't at literal corners because of existing part placement, but land close enough to the left edge/top/bottom to still give reasonable 4-point support. Boss pilot hole (in the FDM case) should target the self-tapping spec for M2.5 into whatever plastic you're printing in — the 2.7mm PCB hole is just clearance, the case boss does the actual threading.
- **All components are on the top side only (F.Cu)** — nothing is placed on the bottom copper layer, so the case's bottom shell only needs to clear solder joints (~0.3–0.5 mm), not components.

## Component positions (X, Y from board bottom-left corner) and mechanical notes

| Ref | Part | Function | X (mm) | Y (mm) | Rotation | Notes |
|---|---|---|---|---|---|---|
| SW3 | ALPS SKQUCAA010 | 5-way nav switch (up/down/left/right/select) | 25.6 | 26.83 | 0° | **Tallest component on the board.** See below — this drives your minimum internal case height. Reference was `J2` in earlier revisions of this doc; renamed to `SW3` on the schematic/PCB to match the SW1/SW2 naming convention. |
| U2 | MSP430FR2355TDBTR | MCU, TSSOP-38 | 23.15 | 10.5 | 180° | Body 9.65–9.75 × 4.35–4.45 mm, 1.2 mm max height. Low profile, not case-critical. |
| U1 | TPS63900 | Buck-boost regulator, WSON-10 | 7.71 | 49.5 | 180° | Body 2.5 × 2.5 mm, 0.8 mm max height. Negligible. |
| L1 | Murata DFE201612E-2R2M | Regulator inductor, 2.2 µH | 3.0 | 49.5 | — | Verified 2026-07-22: schematic symbol, footprint (`IND_DFE2016_MUR`, sourced from a directory literally named `DFE201612E_2R2M_P2`), and TPS63900's own Table 8-2 recommended-inductor list all agree on this exact part — 2.0×1.6×1.2mm body, 2.2A saturation current, 116mΩ DCR. An earlier note in this doc claimed a mismatch against a "DFE252012" part, but that part number doesn't appear in the datasheet at all (likely confused with the table's other listed alternate, DFE252010F) — there was never an actual mismatch. Height ~1.2mm, not case-critical. |
| SW1 | ALPS/SKRPACE010 | "DEAL" tact button | 35.0 | 9.425 | 0° | Verified against ALPS' official SKRP-series catalog (`skrpace010_datasheet.pdf`, Drawing No.1): body **4.2 × 3.2 × 2.5mm** (W×D×H), top-push actuator, **0.2mm travel**, dome-cap style stem sits flush with the top face (no separate exposed stem like the nav switch). Land pattern 5.2 × 2.8mm footprint (4 pads). Cutout just needs a small hole/dome clearance right above the switch top face, not a tall stem like SW3. |
| SW2 | ALPS/SKRPACE010 | "UNDO" tact button | 35.0 | 50.575 | 0° | Same part as SW1, same numbers. |
| J1 | GCT FFC2B35-10-T | FPC connector to LCD | 46.27 | 30.0 | 90° | Replaces the originally-specced Molex 51441-1093, which is obsolete/EOL — same mechanical family (bottom-contact, front-flip ZIF), same footprint position/rotation. Pins 11/12 are the connector's mechanical/shield pads (not LCD signals) and are tied to GND, not a leftover mismatch. Verified against GCT's official drawing (`gct_ffc2b35_datasheet.pdf`): **height = 2.0mm** above PCB (confirmed in the part's own title block), and for the 10-position variant specifically, body dimensions **A=9.4mm, B=4.50mm, C=5.60mm, D=6.50mm** per GCT's per-position-count dimension table. Low profile — not case-height-critical, but the FPC cable exits to the side (front-flip actuator), so leave a clear lateral path for the flex cable at the board edge near (46.27, 30.0). |
| J3 | Generic 1×4, 2.54mm pin header, vertical | SBW programming header | 3.19 | 3.0 | 90° | Standard break-away header. Typical total pin height above the board is ~8.5 mm (insulator + pins) for this style — verify against whatever specific header you use if it needs a case opening; if it's for occasional reprogramming only, you may not need a cutout at all. |
| J4 | JST PH S2B-PH-K-S, 2-pin | Battery input (+BATT/GND) | 3.5 | 37.5 | 90° | Side-entry, through-hole, 2mm-pitch JST PH housing. Verified against JST's official PH-series catalog (`jst_ph_connector_datasheet.pdf`): for the 2-circuit side-entry header, housing dimensions **A=2.0mm** (pin pitch span), **B=5.9mm** (overall housing length) per JST's model table (page 3). PCB hole is ⌀0.7+0.1/-0mm, pins on 2.0mm pitch, applicable board thickness 0.8-1.6mm (this board's 1.6mm is within range). The catalog states an 8mm mounting height / 4.5mm width explicitly for the **top-entry** version only — side-entry sits lower/flatter since the wire exits horizontally instead of up, but I don't have that exact height broken out as cleanly as the top-entry figure; the housing footprint (A/B above) is solid, treat height as still approximate. Pin 1 is silk-marked on the physical housing per JST's diagrams — useful for the polarity check below. |

## The nav switch (SW3) — the number that sets your case height

From ALPS' SKQU-series datasheet (`skqucaa010_datasheet.pdf`), this is drawing #3 ("With Center Push Type", snap-in/through-hole) — page 3 has the full mechanical drawing if you need to re-derive anything below:
- **Footprint/body**: 10 mm × 10 mm square
- **Mounting hole pattern**: 10.3 × 6.5 mm (four ⌀1.2mm + two ⌀1mm through-holes)
- **Total height from PCB surface to top of the bare stem**: 10 mm
- **Actuator travel**: 0.4 mm lateral in each of the 4 directions (per the datasheet spec — see the pivot/scaling note below for what this means at other heights), 0.2 mm center-push travel (straight down, does not scale with cap height)

### Stem dimensions (for the knob you're modeling in FreeCAD)

- **Stem cross-section**: the mating tip is a keyed/cross-shaped post inscribed in a 3.2 × 3.2 mm square — not a plain round or square post. The datasheet's top-view drawing (page 3) shows the exact keyed profile; trace that if you want a precise interlocking fit rather than a loose friction-fit sleeve.
- **Stem exposed length**: the switch's fixed collar (the part that doesn't move) tops out at 5.8 mm above the PCB; the stem runs from there to 10 mm. That's **4.2 mm of stem** available for a knob to grip.
- **Center of stem rotation (pivot point)**: 1.23 mm above the PCB surface. The stem tilts about this point, not about its own base or the collar top — this is what the clearance math below is built on.

### Sizing the case cutout around a knob

The datasheet's 0.4 mm travel figure is measured 2.9 mm below the stem top (i.e. at ~7.1 mm above the PCB) — it does **not** directly apply at the stem tip, and it applies even less at the top of a knob that extends past the stem. Because the stem pivots about the 1.23 mm point above, lateral displacement scales with height above that pivot. The implied per-direction tilt angle is:

	θ = atan(0.4 mm / (7.1 − 1.23) mm) = atan(0.4 / 5.87) ≈ 3.9°

so displacement at any height `h` above the PCB is:

	lateral displacement(h) ≈ (h − 1.23 mm) × tan(3.9°)

- At the bare stem tip (h = 10 mm): (10 − 1.23) × tan(3.9°) ≈ **0.60 mm**
- Example — a knob whose top sits 5 mm above the bare stem tip (h = 15 mm): (15 − 1.23) × tan(3.9°) ≈ **0.94 mm**

Recompute this once you've settled on an actual knob height in FreeCAD — the case opening needs to clear the *knob's* swing, not the bare stem's 0.4 mm spec.

This is the tallest thing on the board by a wide margin (next tallest verified part is the header pins at ~8.5mm) — **plan for at least ~10mm of clearance above the PCB on the component side for the bare switch**, plus however much height your knob design adds on top.

## LCD module (not on this PCB — connects via FPC to J1)

From the Sharp `LS013B7DH03` datasheet (`sharp_ls013b7dh03_memory_lcd_datasheet.pdf`, section 8, "Outline Dimension"):
- **Module outline**: 26.60 × 30.30 mm (±0.2mm)
- **Active/viewing area**: 23.04 × 23.04 mm (128×128 pixels, 1.28" diagonal)
- **Module thickness**: ~1.6mm panel, up to ~3.63mm total including the stiffener/FPC connector area at the bottom edge
- **FPC connector recommendation**: Molex 51441-1093 (bottom contact) — the board's `J1` now uses the GCT FFC2B35-10-T instead (Molex part went obsolete), a mechanically-equivalent bottom-contact/front-flip substitute, not Sharp's own recommended part
- **FPC bend**: minimum bend radius 0.45mm inner diameter, bend zone 0.8–6.0mm from the glass edge, don't bend backward (toward polarizer side), max 3 bend cycles

This module isn't part of the PCB — it sits wherever you place it in the case, connected back to `J1` by the FPC tail. You'll want a case cutout matching (or slightly larger than) the 23.04×23.04mm active area, with a ledge/bezel covering the ~1.78mm border out to the 26.60×30.30mm module edge.

## Battery holder (not on this PCB — connects via J4)

**Selected 2026-07-21: Adafruit #4194, 2×AA Open Battery Holder with JST-PH Connector** — no switch, chosen to match the rest of the design, which has no power switch anywhere (TPS63900 was picked specifically for its 75nA quiescent current so the board can be always-on).

- **Holder body**: 58.2 × 32 × 13.6mm — open/skeletal frame (not a sealed box), cells side-by-side. The case walls provide the enclosure, not the holder.
- **Cable**: ~6" (150mm), terminated in a genuine JST-PH 2-pin connector — mates directly with `J4` as designed, no soldering or crimping needed.
- Plan for roughly a 58 × 32mm clear area in the case for the holder itself, plus a cable run from wherever you place it to `J4` at board position (3.5, 37.5).

**Before first plug-in: verify polarity.** `J4` pin 1 (the square pad in the KiCad footprint) is `+BATT`; Adafruit's product page doesn't publish which physical pin of their JST-PH cable that corresponds to. The TPS63900 datasheet doesn't document any reverse-polarity protection on VIN, so confirm with a continuity check against the board's pin-1 pad before connecting the battery holder for the first time — a swapped connector would put reverse voltage directly on `U1`.

## Open items before you finalize the case

1. ~~**Add mounting holes to the PCB**~~ Resolved 2026-07-22 — 4× M2.5 NPTH added (H1-H4), see the Board section above for positions.
2. ~~**Get real mechanical drawings** for: SKRPACE010 (SW1/SW2), GCT FFC2B35-10-T (J1), JST PH S2B-PH-K (J4)~~ Resolved 2026-07-22 — official datasheets pulled (`skrpace010_datasheet.pdf`, `gct_ffc2b35_datasheet.pdf`, `jst_ph_connector_datasheet.pdf`), see the component table above. J4's exact side-entry mounting height is still a bit softer than the other two (see its table note) — revisit if the case design gets tight on Z-height near the battery connector.
3. ~~**Confirm L1's actual part number** matches the footprint~~ Resolved 2026-07-22 — no mismatch existed. Symbol (DFE201612E-2R2M), footprint, and TPS63900's own recommended-inductor table all agree; the earlier "DFE252012" concern was based on a part number that isn't actually in the datasheet. See the component table above.
4. ~~**Decide on battery form factor**~~ Resolved 2026-07-21 — Adafruit #4194, see the Battery holder section above. Still need to verify cable polarity against `J4` pin 1 before first connection (see note above).
5. **Nav switch knob (SW3)** — no off-the-shelf ALPS accessory fits the SKQU stem (ALPS' SK2AA cap line is for the mechanically different SKHC/SKHH/SKQE families, not SKQU); being modeled from scratch in FreeCAD using the stem dimensions above. Once a height is chosen, redo the case-cutout clearance calc in the section above with the real number.
