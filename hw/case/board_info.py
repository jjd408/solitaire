"""Writes what the case needs to know about the board to out/board.json: its size, the mounting holes, each
button with its row and label, and the battery pads. Read from ../sol/sol.kicad_pcb (the parts as placed) and
../sol/layout.py (the board's size and the bottom row's names).

    python3 board_info.py

Coordinates are the case's: millimetres from the board's bottom-left corner, x right, y up (as in the board's
STEP export with --drill-origin and the placement files).
"""
import json
import os
import sys

import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "sol"))
import layout  # noqa: E402  (the board's constants; its main() only runs as a script)


def main():
    board = pcbnew.LoadBoard(layout.PCB)
    fps = {fp.GetReference(): fp for fp in board.GetFootprints()}

    def at(ref):
        p = fps[ref].GetPosition()
        return round(pcbnew.ToMM(p.x) - layout.OX, 3), round(layout.H - (pcbnew.ToMM(p.y) - layout.OY), 3)

    names = dict(layout.BOTTOM_ROW)
    buttons = []
    for ref in sorted((r for r in fps if r.startswith("SW")), key=lambda r: int(r[2:])):
        n = int(ref[2:])
        row = "suits" if n >= 13 else "stacks" if 4 <= n <= 10 else "bottom"
        x, y = at(ref)
        buttons.append({"ref": ref, "x": x, "y": y, "row": row, "label": names.get(ref, "")})
    info = {
        "width": layout.W, "height": layout.H, "corner_radius": layout.R,
        "holes": [{"x": x, "y": round(layout.H - y, 3)} for x, y in layout.HOLES],
        "buttons": buttons,
        "battery_pads": [dict(zip(("x", "y"), at(r)), ref=r) for r in ("TP1", "TP2")],
    }
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    with open(os.path.join(HERE, "out", "board.json"), "w") as f:
        json.dump(info, f, indent=1)
    print(f"board.json: {len(buttons)} buttons, {len(info['holes'])} holes")


if __name__ == "__main__":
    main()
