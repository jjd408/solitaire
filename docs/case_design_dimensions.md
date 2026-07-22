# Case Design Dimensions

Pulled from the current PCB (`hw/solitaire/solitaire.kicad_pcb`, commit `6e86350`) and the datasheets in this `docs/` folder. Anything I couldn't verify from a real source is marked **TBD** rather than guessed — don't use unverified numbers for a case cutout.

All coordinates below are **relative to the board's bottom-left corner** (i.e. the board's own min-X/min-Y edge = (0,0)), not KiCad's internal sheet coordinates.

## Board

- **Outline**: 100.0 mm × 60.0 mm rectangle (simple rect, no cutouts/notches yet)
- **Thickness**: 1.6 mm (KiCad default — no custom stackup is defined in the project, so confirm this is actually what you want before fab)
- **Mounting holes**: **none placed yet.** There are currently zero `MountingHole` footprints or NPTH holes on the board. If the case needs screw bosses / standoffs, those holes need to be added to the PCB first so the case and board agree on hole position — worth doing before you lock case dimensions.
- **All components are on the top side only (F.Cu)** — nothing is placed on the bottom copper layer, so the case's bottom shell only needs to clear solder joints (~0.3–0.5 mm), not components.

## Component positions (X, Y from board bottom-left corner) and mechanical notes

| Ref | Part | Function | X (mm) | Y (mm) | Rotation | Notes |
|---|---|---|---|---|---|---|
| SW3 | ALPS SKQUCAA010 | 5-way nav switch (up/down/left/right/select) | 25.6 | 26.83 | 0° | **Tallest component on the board.** See below — this drives your minimum internal case height. Reference was `J2` in earlier revisions of this doc; renamed to `SW3` on the schematic/PCB to match the SW1/SW2 naming convention. |
| U2 | MSP430FR2355TDBTR | MCU, TSSOP-38 | 23.15 | 10.5 | 180° | Body 9.65–9.75 × 4.35–4.45 mm, 1.2 mm max height. Low profile, not case-critical. |
| U1 | TPS63900 | Buck-boost regulator, WSON-10 | 7.71 | 49.5 | 180° | Body 2.5 × 2.5 mm, 0.8 mm max height. Negligible. |
| L1 | Murata DFE201612E-2R2M(-P2), 2.2 µH | Regulator inductor | 3.0 | 49.5 | — | Footprint `IND_DFE2016_MUR` matches — this exact part is listed in the TPS63900 datasheet's Table 8-2 "List of Recommended Inductors" (2.0×1.6×1.2mm, 2.4A sat., 116mΩ DCR). Height ~1.2mm, not case-critical. |
| SW1 | ALPS/SKRPACE010 | "DEAL" tact button | 35.0 | 9.425 | 0° | **No local datasheet for SKRPACE010** — I don't have a verified height. Pull the ALPS SKRPACE010 mechanical drawing before sizing the case cutout/actuator. |
| SW2 | ALPS/SKRPACE010 | "UNDO" tact button | 35.0 | 50.575 | 0° | Same part as SW1, same caveat. |
| J1 | **GCT FFC2B35-10-T** (was Molex 51441-1093, now obsolete) | FPC connector to LCD | 46.27 | 30.0 | 90° | Swapped 2026-07-21 — see the LCD module section below for the full story. Mated height 2.0mm. Position unchanged from the old Molex placement; rotation re-verified by render (cable-entry edge still faces the LCD outline rectangle, same as before). |
| J3 | Generic 1×4, 2.54mm pin header, vertical | SBW programming header | 3.19 | 3.0 | 90° | Standard break-away header. Typical total pin height above the board is ~8.5 mm (insulator + pins) for this style — verify against whatever specific header you use if it needs a case opening; if it's for occasional reprogramming only, you may not need a cutout at all. |
| J4 | JST PH S2B-PH-K, 2-pin | Battery input (+BATT/GND) | 3.5 | 37.5 | 90° | Side-entry (horizontal) 2mm-pitch JST PH housing. In-plane footprint envelope ~6.9 × 8.6 mm. I don't have a verified mated height from a local datasheet — pull JST's PH-series drawing before finalizing the battery-wire exit/cutout. |

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
- **FPC connector recommendation**: Sharp's datasheet calls out Molex 51441-1093 (bottom contact) — **now obsolete, see replacement below**.
- **FPC bend**: minimum bend radius 0.45mm inner diameter, bend zone 0.8–6.0mm from the glass edge, don't bend backward (toward polarizer side), max 3 bend cycles

This module isn't part of the PCB — it sits wherever you place it in the case, connected back to `J1` by the FPC tail. You'll want a case cutout matching (or slightly larger than) the 23.04×23.04mm active area, with a ledge/bezel covering the ~1.78mm border out to the 26.60×30.30mm module edge.

### J1 connector replacement: Molex 51441-1093 is obsolete (found 2026-07-21, swapped same day)

Checked DigiKey: Molex 0514411093 is listed **"Obsolete and no longer manufactured."** DigiKey's cross-reference suggested two replacements, both 0.5mm-pitch/10-position/bottom-contact:

- **GCT FFC2B35-10-T (chosen)** — its datasheet keywords describe it as "0.5mm Pitch Side Entry, Bottom Contact, SMT, Height=2.0mm, Front Flip," which matches the Molex Easy-On mechanism (same front-flip ZIF actuator, same bottom-contact side-entry style) rather than just matching on pitch/position count alone. For the 10-contact variant: body length 9.4mm, **mated height 2.0mm**. Also directly stocked at JLCPCB (part C6947499), which lines up with `docs/lcsc_jlcpcb_fab_assembly_checklist.md`.
- Hirose FH34SRJ-10S-0.5SH(50) — also 0.5mm/10-position, but it's a "back actuator" part built for high-speed signal work (USB3.1/PCIe/eDP) — different flip mechanism than what's already assumed in the layout, more connector than a slow SPI display link needs. Not used.

**Swap done 2026-07-21.** User downloaded GCT's real symbol/footprint (`hw/solitaire/symbols-footprints/FFC2B35_10_T/`, registered in `fp-lib-table`/`sym-lib-table`) rather than having me hand-derive a footprint. On the schematic side, `J1`'s pin-to-net wiring already matched the Sharp datasheet's real terminal numbers 1:1 (pin1=SCLK...pin10=VSSA, verified against `solitaire.net`), so that didn't need to change — but the GCT symbol's pin *graphics* are laid out differently from the old Molex symbol (one column of 10 vs. two columns of 6), which broke the existing wires for pins 6-10 until rewired: pins 6-8 (VCC) and 9-10 (GND, via a new `#PWR019` symbol) got new short wire chains to match the new pin positions; pins 11/12 (the connector's 2 mechanical/shield pads, tied to GND) needed 2 extra pins added to the symbol definition since GCT's stock symbol only exposed 1-10. Confirmed via `kicad-cli sch erc` (back to the same 31 baseline violations, no new errors) and a render.

On the PCB side, the footprint was fully replaced with GCT's real pad geometry (10× 0.5mm-pitch signal pads + 2 mechanical pads, same net assignments as before) at the same position/rotation as the old Molex part. Checked via `kicad-cli pcb drc` (no new violation categories beyond what's inherent to any 0.5mm-pitch part on an unrouted board) and a render confirming the connector's cable-entry edge still faces the LCD outline rectangle, same physical orientation as the old part had.

## Battery holder (not on this PCB — connects via J4)

**Selected 2026-07-21: Adafruit #4194, 2×AA Open Battery Holder with JST-PH Connector** — no switch, chosen to match the rest of the design, which has no power switch anywhere (TPS63900 was picked specifically for its 75nA quiescent current so the board can be always-on).

- **Holder body**: 58.2 × 32 × 13.6mm — open/skeletal frame (not a sealed box), cells side-by-side. The case walls provide the enclosure, not the holder.
- **Cable**: ~6" (150mm), terminated in a genuine JST-PH 2-pin connector — mates directly with `J4` as designed, no soldering or crimping needed.
- Plan for roughly a 58 × 32mm clear area in the case for the holder itself, plus a cable run from wherever you place it to `J4` at board position (3.5, 37.5).

**Before first plug-in: verify polarity.** `J4` pin 1 (the square pad in the KiCad footprint) is `+BATT`; Adafruit's product page doesn't publish which physical pin of their JST-PH cable that corresponds to. The TPS63900 datasheet doesn't document any reverse-polarity protection on VIN, so confirm with a continuity check against the board's pin-1 pad before connecting the battery holder for the first time — a swapped connector would put reverse voltage directly on `U1`.

## Open items before you finalize the case

1. **Add mounting holes to the PCB** if the case will screw to the board — none exist yet, and case screw-boss positions should be locked to real PCB holes, not guessed.
2. **Get real mechanical drawings** for: SKRPACE010 (SW1/SW2), JST PH S2B-PH-K (J4) — I didn't have local datasheets for these two. (J1's Molex part turned out to be obsolete — see item 6.)
3. ~~**Confirm L1's actual part number** matches the footprint~~ Resolved — I'd misread the datasheet: DFE201612E-2R2M is directly listed in TPS63900's Table 8-2 (List of Recommended Inductors) and matches the `IND_DFE2016_MUR` footprint. I'd confused it with Table 8-5, a separate BOM for TI's own 3.3V characterization board that happens to use a different Murata part (DFE252012F-2R2M) — that's not "the" recommended part, just what one eval board used.
4. ~~**Decide on battery form factor**~~ Resolved 2026-07-21 — Adafruit #4194, see the Battery holder section above. Still need to verify cable polarity against `J4` pin 1 before first connection (see note above).
5. **Nav switch knob (SW3)** — no off-the-shelf ALPS accessory fits the SKQU stem (ALPS' SK2AA cap line is for the mechanically different SKHC/SKHH/SKQE families, not SKQU); being modeled from scratch in FreeCAD using the stem dimensions above. Once a height is chosen, redo the case-cutout clearance calc in the section above with the real number.
6. ~~**Swap J1's footprint**~~ Resolved 2026-07-21 — GCT FFC2B35-10-T, see the LCD module section above.
