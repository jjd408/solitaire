#!/usr/bin/env python3
"""Places the Solitaire board: outline, mounting holes, parts, the display's outline and labels.

Run from this folder with KiCad's Python (`python3 layout.py`); then `route.py` routes it. Both rewrite
sol.kicad_pcb, keeping its footprints (and their nets, from the schematic) but replacing everything this
script and the router make. Coordinates below are millimetres from the board's top-left corner.

The board, front side (all parts are on the front):

    +----------------------------------------------------------------+
    |  o   BATT        +------------------------+               o    |
    |      + -         |                        |                    |
    |                  |   LS013B7DH05 glass    |                    |
    |  CFG  U2 L1      |   24.68 x 30.0         |                    |
    |  R1-3 C1 C2      |                        |                    |
    |                  +----+    FPC     +------+                    |
    |                       |            |       U1 (MCU)    J3 SBW  |
    |                 C4 C3 [ connector  ] C5                        |
    |          [S1]     [S2]      [S3]      [S4]           suits     |
    |  [1]  [2]  [3]  [4]  [5]  [6]  [7]  [8]  [9]          stacks   |
    |  o            [SW1]   [SW2]   [SW3]                        o   |
    +----------------------------------------------------------------+

The display lies face up on the board with its FPC running straight down into the connector (the library's
pin-1-to-pad-1 orientation; see ../README.md), so nothing may sit under the glass or the FPC.
"""
import json
import os

import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
PCB = os.path.join(HERE, "sol.kicad_pcb")
PRO = os.path.join(HERE, "sol.kicad_pro")
KICAD_FP = "/usr/share/kicad/footprints"

OX, OY = 100.0, 100.0           # where the board's top-left corner sits on KiCad's page
W, H, R = 64.0, 80.0, 3.0       # board size and corner radius

# The display (LS013B7DH05): glass and FPC tail, as in ../lib/make_lcd_model.py
GLASS_W, GLASS_H = 24.68, 30.0
FPC_W, FPC_LEN, FPC_IN = 9.47, 13.63, 2.63
CONN_X, CONN_Y = W / 2 + 0.05, 46.0                        # the connector's pad row (x on the router's grid)
GLASS_X = CONN_X - GLASS_W / 2                             # the glass's top-left corner
GLASS_Y = CONN_Y - (FPC_LEN - FPC_IN) - GLASS_H
# The FPC's end goes about FPC_IN mm into the connector past its pad row, so the glass's bottom edge sits
# FPC_LEN - FPC_IN above it (the outline footprint in ../lib assumes the same). Panasonic and Sharp leave the
# exact depth to the case design, so allow ±0.5 mm there.

# Reference: (x, y, rotation). Rotation is KiCad's, counter-clockwise in degrees.
STACK_PITCH, ROW_PITCH = 6.5, 9.75
PLACE = {
    # display connector, rotated so the FPC comes in from above; caps beside it, clear of the FPC
    "DS1": (CONN_X, CONN_Y, 180),
    "C3": (26.5, 46.0, 270),   # 1uF VDDA-VSSA
    "C4": (24.9, 46.0, 270),   # 1uF VDD-VSS
    "C5": (38.2, 48.6, 270),   # 0.1uF DISP
    # MCU right of the connector: SCS/SI/SCLK (pins 16-18) face the connector's signal pads
    "U1": (46.0, 42.0, 0),
    "C6": (40.4, 41.0, 90),    # 0.1uF at DVCC
    "C8": (38.9, 41.0, 90),    # 4.7uF at DVCC
    # Spy-Bi-Wire header on the right edge, its RST parts beside it
    "J3": (60.5, 36.5, 0),
    "R4": (55.2, 39.6, 90),    # 47k RST pull-up
    "C7": (55.2, 43.4, 90),    # 1nF RST
    # power: battery pads, TPS63900 and its parts, left of the display
    "TP1": (6.0, 11.0, 0),     # Batt+
    "TP2": (6.0, 15.0, 0),     # Batt-
    "U2": (11.0, 22.0, 0),
    "L1": (14.4, 22.0, 90),    # LX1 (pin 2) up toward U2 pin 9, LX2 down toward pin 7
    "C1": (11.0, 19.3, 180),   # 10uF in, VIN pad by U2 pin 10
    "C2": (11.6, 24.7, 180),   # 22uF out, VOUT pad below U2 pin 6
    "R1": (6.6, 20.6, 180),    # CFG1 20.5k
    "R2": (6.6, 22.15, 180),   # CFG2 511
    "R3": (6.6, 23.7, 180),    # CFG3 13.3k
}
# Buttons, in the simulator's arrangement: suits (SW13-16), stacks 1-9 (SW4-12), then SW1-3.
# SW4-16 have their signal pads (2) on the bottom, so they're turned over to face the MCU above them;
# SW1-3's signal pads (1) are already on top.
for i in range(4):
    PLACE[f"SW{13 + i}"] = (W / 2 + (i - 1.5) * ROW_PITCH, 56.0, 180)
for i in range(9):
    PLACE[f"SW{4 + i}"] = (W / 2 + (i - 4) * STACK_PITCH, 64.0, 180)
for i in range(3):
    PLACE[f"SW{1 + i}"] = (W / 2 + (i - 1) * ROW_PITCH, 72.0, 0)

HOLES = [(3.5, 3.5), (W - 3.5, 3.5), (3.5, H - 3.5), (W - 3.5, H - 3.5)]

# Silkscreen labels: (text, x, y, size)
LABELS = [("SOLITAIRE", W / 2, 77.0, 1.2), ("+", 3.2, 11.0, 1.2), ("−", 3.2, 15.0, 1.2),
          ("2xAA", 6.0, 7.6, 0.9), ("SBW", 60.5, 33.2, 0.9),
          ("3V0", 57.6, 36.5, 0.8), ("TST", 57.6, 39.04, 0.8), ("RST", 57.6, 41.58, 0.8),
          ("GND", 57.6, 44.12, 0.8)]
for i, s in enumerate(["S1", "S2", "S3", "S4"]):
    LABELS.append((s, W / 2 + (i - 1.5) * ROW_PITCH, 59.0, 0.8))
for i in range(9):
    LABELS.append((str(i + 1), W / 2 + (i - 4) * STACK_PITCH, 67.0, 0.8))
for i in range(3):
    LABELS.append((f"SW{i + 1}", W / 2 + (i - 1) * ROW_PITCH - 4.3, 72.0, 0.8))

def mm(x, y):
    return pcbnew.VECTOR2I(pcbnew.FromMM(OX + x), pcbnew.FromMM(OY + y))


def shape(board, layer, kind, width=0.1):
    s = pcbnew.PCB_SHAPE(board)
    s.SetShape(kind)
    s.SetLayer(layer)
    s.SetWidth(pcbnew.FromMM(width))
    return s


def outline(board):
    e = pcbnew.Edge_Cuts
    for (x1, y1, x2, y2) in [(R, 0, W - R, 0), (W, R, W, H - R), (W - R, H, R, H), (0, H - R, 0, R)]:
        s = shape(board, e, pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(mm(x1, y1))
        s.SetEnd(mm(x2, y2))
        board.Add(s)
    for (cx, cy, sx, sy) in [(R, R, 0, R), (W - R, R, W - R, 0), (W - R, H - R, W, H - R), (R, H - R, R, H)]:
        s = shape(board, e, pcbnew.SHAPE_T_ARC)
        s.SetCenter(mm(cx, cy))
        s.SetStart(mm(sx, sy))
        s.SetArcAngleAndEnd(pcbnew.EDA_ANGLE(90, pcbnew.DEGREES_T), True)
        board.Add(s)


def board_only(fp):
    fp.SetAttributes(fp.GetAttributes() | pcbnew.FP_BOARD_ONLY | pcbnew.FP_EXCLUDE_FROM_BOM
                     | pcbnew.FP_EXCLUDE_FROM_POS_FILES)


def display(board):
    """The glass and FPC: a board-only footprint with their outline, courtyard and the 3D model."""
    fp = pcbnew.FootprintLoad(os.path.join(HERE, "..", "lib", "solitaire.pretty"), "LCD_Sharp_LS013B7DH05_Outline")
    fp.SetFPIDAsString("solitaire:LCD_Sharp_LS013B7DH05_Outline")
    fp.SetReference("LCD1")
    fp.SetValue("LS013B7DH05")
    fp.SetPosition(mm(GLASS_X, GLASS_Y + GLASS_H))   # its origin: the glass's bottom-left corner
    board.Add(fp)


def holes(board):
    for i, (x, y) in enumerate(HOLES):
        fp = pcbnew.FootprintLoad(os.path.join(KICAD_FP, "MountingHole.pretty"), "MountingHole_2.2mm_M2")
        fp.SetReference(f"H{i + 1}")
        board_only(fp)
        fp.SetPosition(mm(x, y))
        fp.Reference().SetVisible(False)
        board.Add(fp)


def labels(board):
    for text, x, y, size in LABELS:
        t = pcbnew.PCB_TEXT(board)
        t.SetText(text)
        t.SetLayer(pcbnew.F_SilkS)
        t.SetPosition(mm(x, y))
        t.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(size), pcbnew.FromMM(size)))
        t.SetTextThickness(pcbnew.FromMM(max(0.12, size * 0.15)))
        board.Add(t)


def net_classes():
    """Power nets 0.3 mm (0.25 mm where they leave the TPS63900's 0.5 mm-pitch pads), the rest 0.2 mm."""
    with open(PRO) as f:
        p = json.load(f)
    ns = p["net_settings"]
    default = next(c for c in ns["classes"] if c["name"] == "Default")
    power = dict(default, name="Power", track_width=0.3, priority=0)
    ns["classes"] = [default, power]
    ns["netclass_patterns"] = [{"netclass": "Power", "pattern": n}
                               for n in ["+3V0", "/VBAT", "GND", "Net-(U2-LX1)", "Net-(U2-LX2)"]]
    ds = p["board"]["design_settings"]
    ds["track_widths"] = [0.0, 0.2, 0.3]
    ds["via_dimensions"] = [{"diameter": 0.0, "drill": 0.0}, {"diameter": 0.6, "drill": 0.3}]
    ds["rules"]["min_copper_edge_clearance"] = 0.5
    ds["rules"]["min_clearance"] = 0.2
    ds["rules"]["min_track_width"] = 0.2
    ds["rules"]["min_through_hole_diameter"] = 0.2   # the TPS63900 footprint's thermal vias
    ds["rules"]["min_resolved_spokes"] = 1            # a small pad's one spoke carries this board's milliamps
    with open(PRO, "w") as f:
        json.dump(p, f, indent=2)
        f.write("\n")


def main():
    board = pcbnew.LoadBoard(PCB)
    # start over: drop the board-only footprints, tracks, zones and drawings (footprints first: after
    # removing drawings, pcbnew's footprint list can hold an object Python can't use)
    for fp in [f for f in board.GetFootprints() if f.GetReference().startswith(("H", "LCD"))]:
        board.Delete(fp)
    for t in list(board.GetTracks()):
        board.Delete(t)
    for z in list(board.Zones()):
        board.Delete(z)
    for d in list(board.GetDrawings()):
        board.Delete(d)

    outline(board)
    holes(board)
    display(board)
    labels(board)
    fps = {fp.GetReference(): fp for fp in board.GetFootprints()}
    missing = set(PLACE) ^ {r for r in fps if not r.startswith(("H", "LCD"))}
    if missing:
        raise SystemExit(f"placement and board disagree about: {sorted(missing)}")
    for ref, (x, y, rot) in PLACE.items():
        fp = fps[ref]
        fp.SetOrientationDegrees(rot)
        fp.SetPosition(mm(x, y))
        # designators go on the assembly drawing; the silkscreen carries the labels above
        fp.Reference().SetLayer(pcbnew.F_Fab)
        fp.Reference().SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(0.6), pcbnew.FromMM(0.6)))
        fp.Reference().SetTextThickness(pcbnew.FromMM(0.1))
        fp.Reference().SetPosition(fp.GetPosition())
        for item in fp.GraphicalItems():
            if isinstance(item, pcbnew.PCB_TEXT) and item.GetLayer() == pcbnew.F_SilkS:
                item.SetLayer(pcbnew.F_Fab)
    # the TPS63900's exposed pad and its thermal vias join the ground pour solidly, not through spokes
    fps["U2"].SetLocalZoneConnection(pcbnew.ZONE_CONNECTION_FULL)
    board.Save(PCB)
    net_classes()
    print(f"placed {len(PLACE)} parts on a {W:g} x {H:g} mm board")


if __name__ == "__main__":
    main()
