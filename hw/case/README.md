# The case

A 3D-printed case for the Solitaire board: a front shell with the display window and the buttons' holes, a back
shell that holds the 2 × AA battery holder, and 16 button caps. It's generated from the board, so moving a part
on the board moves the case with it.

```
sh make_case.sh          (from hw/case: about a minute)
```

It reads the board (`../sol/sol.kicad_pcb`), builds the case in FreeCAD, checks the fit against the board's 3D
model, and writes to `out/`:

| File | What it is | Print |
| --- | --- | --- |
| `front.stl` | Front shell: plate, window, cap holes, labels, walls, screw posts | 1, face down (as saved) |
| `back.stl` | Back shell: walls, floor, battery cradle, standoffs | 1, back down (as saved) |
| `cap_wide.stl` | Cap for the suit and bottom rows | 9, flange down (as saved) |
| `cap_narrow.stl` | Cap for the seven stacks | 7, flange down (as saved) |
| `case.step`, `case.FCStd` | Everything in place around the board, to look at in FreeCAD | |
| `case-front.png`, `case-section.png` | A front view and a cut through the middle (`python3 draw.py`) | |

Each file is printed in the orientation it's saved in, with no supports: the window's bevel is 45°, and the caps'
flanges sit on the bed.

## What it's made of

```
        caps ──┐  ┌── window (1 mm clear sheet in a pocket under the plate)
   ┌───────▄▄▄─┴──┴────────────────────┐ ← front face            z  7.0
   │  plate ▀▀▀  flange      ▄▄▄▄▄▄    │ ← plate underside       z  5.0
   │ post   ▐▌ switch       display    │
   ╞═══════════════ board ═════════════╡                         z  0 – 1.6
   │ standoff    ┌─── 2 × AA holder ──┐│
   │  (screw)    └────────────────────┘│
   └───────────────────────────────────┘ ← back face             z −17.4
```

- **Outside:** 69 × 85 × 24.4 mm, plus 1.2 mm of the caps. The batteries set the depth: AA cells are 14.5 mm
  across.
- **Buttons:** each cap rests on its switch's stem, 0.05 mm above it; a flange under the plate keeps it in, with
  0.05 mm to spare. A press moves the cap the switch's 0.25 mm of travel. Wide caps are 7.5 × 5 mm, the stacks'
  5 × 5 mm (their switches are only 6.5 mm apart).
- **Display:** the window shows the active area plus 1.2 mm each side, widening at 45° to the front face. A
  **28.9 × 32.4 × 1 mm** clear sheet (acrylic or polycarbonate; cut it a hair smaller) is glued into the pocket
  under the plate. The plate doesn't touch the glass: 2.6 mm between them.
- **Labels:** STOCK, WASTE, NEW, UNDO and OPTIONS, engraved 0.4 mm into the face under the bottom row, 1.4 mm
  tall: as big as fits OPTIONS in the buttons' pitch. They need a fine nozzle (0.25 mm) or a resin printer to come
  out crisp; on a 0.4 mm nozzle, expect them soft.
- **Holding it together:** four **M2 × 8 pan-head screws**, from the back, through the standoffs and the board's
  mounting holes into the front's posts (1.6 mm holes: use thread-forming screws for plastic, or tap them M2). The
  board is clamped between the front posts and the back standoffs.
- **J3, the programming header, is left off**: the case has no room for it. Its plated holes can still be reached
  from the back of the board with the back shell off: press a 4-pin header (or pogo pins) into them to program.

## Putting it together

1. Fit the display to the board (see `../ORDERING.md`, *Fitting the display*) and solder the battery holder's
   leads to TP1 (+) and TP2 (−), long enough to reach the back.
2. Glue the clear window into its pocket under the front's plate.
3. Lay the front face down and drop the caps into their holes, flange down: wide caps in the suit and bottom rows,
   narrow ones in the stacks.
4. Lay the board in, face down, onto the front's posts. Run the battery leads over the board's edge through the
   notch in the wall by the pads.
5. Stick the battery holder into the back's cradle (double-sided tape), cells facing out of the cradle.
6. Put the back on, and screw it together.

**Changing the batteries:** take the back off (4 screws). The board has no power switch; the firmware sleeps
between presses, so the batteries last a long time.

## Things to measure before printing

- **The battery holder:** the design assumes 57.2 × 31.8 × 15.2 mm (Keystone 2462 or similar). Measure yours and
  set `HOLDER` in `case.py`: the back's depth and the cradle follow it.
- **The display's position:** how far the FPC goes into its connector moves the glass up or down by up to
  ±0.5 mm (see `../README.md`). The window's 1.2 mm margin allows for it, but check it on the real board and, if
  needed, move the display's outline on the board, and run `make_case.sh` again.
- **Your printer's fit:** print one cap and the front first. The caps should drop freely through their holes;
  if they bind, raise `CAP_HOLE` (0.25 mm each side now).

Every dimension is a named setting at the top of `case.py`.

## Thinner

With AAA cells (a 2 × AAA holder is about 10.5 mm deep) the case would be about 19.5 mm thick: set `HOLDER` to the
AAA holder's size. The TPS63900 runs from either; AAAs hold about a third of the charge.

## How it's checked

`case.py` fails (and `make_case.sh` with it) unless:

- nothing in the front, back or caps overlaps the board or any part on it (from its 3D model, J3 left out);
- no cap overlaps the front shell or another cap;
- a cap pressed down by the switch's travel touches only its own switch's stem;
- the two shells don't overlap.
