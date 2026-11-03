"""Builds 3D models of the Sharp memory LCDs for case design and KiCad.

Run with FreeCAD's command line:  freecadcmd make_lcd_model.py
Writes 3d/<model>.step and 3d/<model>.FCStd next to this script for each display in MODELS.

Dimensions are from the outline drawings in ../../docs/datasheets/: Figure 5-1 of Sharp spec
LCP-2111042 (LS013B7DH03) and Figure 8-1 of spec LD-26912A (LS013B7DH05). The glass, polarizers and
active area are as drawn; the FPC tail is simplified to a wide section and a narrow contact end, so
treat its outline as approximate and check the drawing before relying on it for clearances.

Coordinates: origin at the glass's bottom-left corner with the display side up (+Z), the FPC leaving
the bottom edge toward -Y. Millimetres.
"""
import os

import FreeCAD as App
import Part

MODELS = {
    "LS013B7DH03": dict(
        glass_w=26.6, glass_h=30.3,
        pol_w=25.6, pol_h=27.2,             # top and bottom polarizers
        pol_inset_x=0.5, pol_inset_top=0.5,
        aa_w=23.04, aa_h=23.04,             # active area
        aa_center_x=13.3, aa_center_y=17.23,
        fpc_length=13.63,                   # below the glass edge
        fpc_wide=9.47, fpc_wide_left=8.565,
        fpc_narrow=5.5,                     # the contact end: 10 contacts at 0.5mm pitch
        fpc_narrow_from=6.0,                # where the tail narrows, below the glass edge (approximate)
        fpc_bond=1.6,                       # ledge on the TFT glass where the FPC is bonded
        # Layer stack from the side view: bottom polarizer, TFT glass, top glass, top polarizer.
        z_pol_bot=0.12, z_tft=0.25, z_top_glass=0.15, z_pol_top=0.226,
    ),
    # The drawing has the FPC at the top; it is flipped here to match the DH03's orientation.
    "LS013B7DH05": dict(
        glass_w=24.68, glass_h=30.0,
        pol_w=24.08, pol_h=27.4,
        pol_inset_x=0.3, pol_inset_top=0.3,
        aa_w=20.88, aa_h=24.36,
        aa_center_x=12.34, aa_center_y=30.0 - 13.78,
        fpc_length=13.63,
        # The tail is the stiffener's width along its length, apart from small notches.
        fpc_wide=9.47, fpc_wide_left=12.34 - 9.47 / 2,
        fpc_narrow=9.47,
        fpc_narrow_from=6.0,
        fpc_bond=30.0 - 28.4,
        z_pol_bot=0.115, z_tft=0.25, z_top_glass=0.15, z_pol_top=0.23,
    ),
}
FPC_THICK = 0.2


def box(w, h, t, x, y, z):
    return Part.makeBox(w, h, t, App.Vector(x, y, z))


def build(name, m, out):
    doc = App.newDocument(name)

    pol_y = m["glass_h"] - m["pol_inset_top"] - m["pol_h"]
    z = 0.0
    parts = {}
    parts["polarizer_bottom"] = box(m["pol_w"], m["pol_h"], m["z_pol_bot"], m["pol_inset_x"], pol_y, z)
    z += m["z_pol_bot"]
    parts["tft_glass"] = box(m["glass_w"], m["glass_h"], m["z_tft"], 0, 0, z)
    z += m["z_tft"]
    tft_top = z
    # The top glass stops short of the bottom edge, leaving the ledge the FPC is bonded to.
    parts["top_glass"] = box(m["glass_w"], m["glass_h"] - m["fpc_bond"], m["z_top_glass"], 0, m["fpc_bond"], z)
    z += m["z_top_glass"]
    parts["polarizer_top"] = box(m["pol_w"], m["pol_h"], m["z_pol_top"], m["pol_inset_x"], pol_y, z)
    z += m["z_pol_top"]
    # The active area as a thin face on the top polarizer, so it shows when placing the window.
    parts["active_area"] = box(m["aa_w"], m["aa_h"], 0.01, m["aa_center_x"] - m["aa_w"] / 2,
                               m["aa_center_y"] - m["aa_h"] / 2, z)

    # FPC: bonded on the ledge, then a wide section and the narrow contact end.
    wide = box(m["fpc_wide"], m["fpc_bond"] + m["fpc_narrow_from"], FPC_THICK, m["fpc_wide_left"],
               -m["fpc_narrow_from"], tft_top)
    narrow_left = m["fpc_wide_left"] + (m["fpc_wide"] - m["fpc_narrow"]) / 2
    narrow = box(m["fpc_narrow"], m["fpc_length"] - m["fpc_narrow_from"], FPC_THICK, narrow_left,
                 -m["fpc_length"], tft_top)
    parts["fpc"] = wide.fuse(narrow).removeSplitter()

    colors = {
        "polarizer_bottom": (0.55, 0.55, 0.55), "tft_glass": (0.75, 0.85, 0.85),
        "top_glass": (0.75, 0.85, 0.85), "polarizer_top": (0.35, 0.38, 0.40),
        "active_area": (0.10, 0.12, 0.12), "fpc": (0.85, 0.55, 0.15),
    }
    objects = []
    for part, shape in parts.items():
        obj = doc.addObject("Part::Feature", part)
        obj.Shape = shape
        if hasattr(obj, "ViewObject") and obj.ViewObject:
            obj.ViewObject.ShapeColor = colors[part]
        objects.append(obj)
    doc.recompute()

    Part.export(objects, os.path.join(out, f"{name}.step"))
    doc.saveAs(os.path.join(out, f"{name}.FCStd"))
    whole = Part.makeCompound([o.Shape for o in objects])
    bb = whole.BoundBox
    print(f"{name} model: {bb.XLength:.2f} x {bb.YLength:.2f} x {bb.ZLength:.3f} mm "
          f"(glass {m['glass_w']} x {m['glass_h']}, FPC to y={bb.YMin:.2f})")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "3d")
    os.makedirs(out, exist_ok=True)
    for name, m in MODELS.items():
        build(name, m, out)


main()
