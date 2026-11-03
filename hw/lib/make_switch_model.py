"""Builds a 3D model of the ALPS SKRPACE010 tact switch for case design and KiCad.

Run with FreeCAD's command line:  freecadcmd make_switch_model.py
Writes 3d/SW_Alps_SKRPACE010.step and .FCStd next to this script.

Dimensions are from the outline drawing in ALPS's SKRP datasheet (../../docs/datasheets/alps_skrp.pdf):
body 4.2 x 3.2, 1.6 high to the housing and 1.8 to the cover, stem 3.0 x 2.2 with R1.1 ends reaching
2.5 above the board, terminals reaching 4.6 across. The terminals' shape is simplified.

Coordinates match the footprint: origin at the switch's centre on the board surface, display side up (+Z).
Millimetres.
"""
import os

import FreeCAD as App
import Part

BODY_W, BODY_H = 4.2, 3.2
HOUSING_T, COVER_TOP = 1.6, 1.8
STEM_W, STEM_H, STEM_R, STEM_TOP = 3.0, 2.2, 1.1, 2.5
TERM_SPAN, TERM_W, TERM_T = 4.6, 0.3, 0.15
TERM_Y = (1.6 + 2.2) / 4            # centred between the 1.6 and 2.2 terminal dimensions


def box(w, h, t, x, y, z):
    return Part.makeBox(w, h, t, App.Vector(x, y, z))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "3d")
    os.makedirs(out, exist_ok=True)
    doc = App.newDocument("SW_Alps_SKRPACE010")

    parts = {}
    parts["housing"] = box(BODY_W, BODY_H, HOUSING_T, -BODY_W / 2, -BODY_H / 2, 0)
    parts["cover"] = box(BODY_W, BODY_H, COVER_TOP - HOUSING_T, -BODY_W / 2, -BODY_H / 2, HOUSING_T)
    # The stem: a rectangle with semicircular ends (R1.1 = half its 2.2 height).
    straight = STEM_W - 2 * STEM_R
    stem = box(straight, STEM_H, STEM_TOP - COVER_TOP, -straight / 2, -STEM_H / 2, COVER_TOP)
    for x in (-straight / 2, straight / 2):
        stem = stem.fuse(Part.makeCylinder(STEM_R, STEM_TOP - COVER_TOP, App.Vector(x, 0, COVER_TOP)))
    parts["stem"] = stem.removeSplitter()
    terms = [box(TERM_SPAN, TERM_W, TERM_T, -TERM_SPAN / 2, y - TERM_W / 2, 0) for y in (-TERM_Y, TERM_Y)]
    parts["terminals"] = terms[0].fuse(terms[1])

    colors = {"housing": (0.15, 0.15, 0.15), "cover": (0.75, 0.75, 0.78), "stem": (0.92, 0.90, 0.85),
              "terminals": (0.85, 0.75, 0.45)}
    objects = []
    for name, shape in parts.items():
        obj = doc.addObject("Part::Feature", name)
        obj.Shape = shape
        if hasattr(obj, "ViewObject") and obj.ViewObject:
            obj.ViewObject.ShapeColor = colors[name]
        objects.append(obj)
    doc.recompute()

    Part.export(objects, os.path.join(out, "SW_Alps_SKRPACE010.step"))
    doc.saveAs(os.path.join(out, "SW_Alps_SKRPACE010.FCStd"))
    bb = Part.makeCompound([o.Shape for o in objects]).BoundBox
    print(f"SW_Alps_SKRPACE010 model: {bb.XLength:.2f} x {bb.YLength:.2f} x {bb.ZLength:.2f} mm")


main()
