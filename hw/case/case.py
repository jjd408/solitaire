"""Builds the Solitaire handheld's case around the board: a front shell, a back shell and 16 button caps.

Run by make_case.sh (FreeCAD's command line: freecadcmd case.py), after board_info.py has written
out/board.json and the board's 3D model has been exported to out/board.step (every part but J3, which is left
off: the case has no room for it). Writes to out/:

    front.stl         the front shell, face down as it prints
    back.stl          the back shell, back down as it prints
    cap_wide.stl      a button cap for the suit and bottom rows (print 9), flange down
    cap_narrow.stl    a button cap for the seven stacks (print 7), flange down
    case.step         everything in place around the board, for checking in FreeCAD or KiCad
    case.FCStd        the same as a FreeCAD document

and checks the fit: nothing in the case overlaps the board or its parts, the caps clear each other and their
holes, and the caps sit just above the switches. Fails (exit 1) if anything doesn't fit.

How it goes together (front face up, z up, the board's bottom at z = 0):

    caps          through holes in the front plate, held in by a flange underneath; each rests on its
                  switch's stem, so a press goes straight to the switch
    front shell   the plate (window, cap holes, engraved labels) and the walls; four posts press on the board
                  around its mounting holes, and take the screws
    the board     sandwiched between the front posts and the back's standoffs
    back shell    the walls and the floor, a cradle for the 2 x AA holder, and four standoffs that the M2
                  screws pass through, from the back into the front posts

The display is protected by a 1 mm clear window (acrylic or polycarbonate) glued into a pocket under the
plate. Batteries are changed by taking the back off (4 screws). The battery leads run from the pads at the
board's top left over the board's edge to the back, through a notch in both shells' walls.

Coordinates: millimetres, from the board's bottom-left corner, x right, y up, as in the board's STEP export.
"""
import json
import os
import sys

import FreeCAD as App
import Mesh
import MeshPart
import Part

V = App.Vector
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# ---- the design's choices (change these, then run make_case.sh again) ----
CLEAR = 0.5             # around the board, inside the walls
WALL = 2.0              # wall thickness
PLATE = 2.0             # front plate thickness
FLOOR = 1.6             # back floor thickness
EDGE_ROUND = 1.0        # rounding on the front and back faces' outer edges
POST_R = 2.5            # front posts, around the board's mounting holes
PILOT_R = 0.8           # their screw holes: 1.6 mm, for M2 thread-forming screws (or tap M2)
PILOT_SKIN = 0.8        # plate left over the end of each screw hole
STANDOFF_R = 3.0        # back standoffs
SCREW_R = 1.15          # M2 clearance through the standoffs and the board
HEAD_R = 2.1            # counterbore for the screw heads (M2 pan head: 3.8 mm across)
HEAD_SEAT = 2.0         # standoff left under each screw head: M2 x 8 screws reach 4.4 mm into the posts

# Button caps: the body shows through the plate, the flange keeps it in
CAP = {"wide": (7.5, 5.0), "narrow": (5.0, 5.0)}         # body, x by y
FLANGE = {"wide": (9.2, 7.4), "narrow": (6.1, 7.4)}      # flange, x by y
FLANGE_T = 0.8          # flange thickness
CAP_HOLE = 0.25         # clearance around a cap body in its hole, each side
CAP_LIFT = 0.05         # cap above its switch's stem, at rest
CAP_PLAY = 0.05         # flange below the plate, at rest
CAP_PROUD = 1.2         # cap above the front face
CAP_ROUND = 0.5         # rounding on a cap's top edges
SWITCH_TRAVEL = 0.25    # the SKRPACE010's travel

# The display window
WINDOW_MARGIN = 1.2     # opening beyond the active area at its narrowest, each side
WINDOW_BEVEL = 1.0      # how much wider it gets at the front face (a 45 degree bevel), each side
LENS_T = 1.0            # the clear window's thickness: its pocket's depth under the plate
LENS_MARGIN = 4.0       # the clear window beyond the active area, each side (its pocket: plus 0.1)

# Labels engraved under the bottom row
LABEL_SIZE = 1.6        # cap height of the letters
LABEL_DEPTH = 0.4
LABEL_GAP = 1.0         # between a bottom-row hole and its label

# The battery holder: a 2 x AA holder, cells side by side (e.g. Keystone 2462: about 57.2 x 31.8 x 15.2 mm).
# Measure yours: the back's depth and the cradle follow these.
HOLDER = (57.2, 31.8, 15.2)
HOLDER_CLEAR = 0.3      # around the holder in its cradle
HOLDER_UNDER = 0.6      # between the holder and the board
CRADLE_H = 5.0          # the cradle's corner ribs: height, thickness, length of each leg
CRADLE_T = 1.2
CRADLE_LEG = 6.0

# The battery leads' notch in the walls, by the pads
NOTCH_DEEP = 1.2        # into the wall (it leaves WALL - NOTCH_DEEP)
NOTCH_LONG = 10.0       # along the wall, centred between the pads
NOTCH_FRONT = 4.5       # how far it goes up the front shell from z = 0
NOTCH_BACK = 4.0        # and down the back shell


def rbox(x0, y0, w, h, r, z0, z1):
    """A box with its vertical edges rounded to r."""
    b = Part.makeBox(w, h, z1 - z0, V(x0, y0, z0))
    if r > 0:
        b = b.makeFillet(r, [e for e in b.Edges if abs(e.Vertexes[0].Point.z - e.Vertexes[-1].Point.z) > 1e-6])
    return b


def cbox(cx, cy, w, h, z0, z1):
    """A box centred on (cx, cy)."""
    return Part.makeBox(w, h, z1 - z0, V(cx - w / 2, cy - h / 2, z0))


def rect_wire(cx, cy, w, h, z):
    return Part.makePolygon([V(cx - w / 2, cy - h / 2, z), V(cx + w / 2, cy - h / 2, z), V(cx + w / 2, cy + h / 2, z),
                             V(cx - w / 2, cy + h / 2, z), V(cx - w / 2, cy - h / 2, z)])


def polygon(wire, deflection=0.01):
    """A wire as straight segments: the font's curves can cross themselves slightly (the S's do), which leaves
    the mesh with crossing facets; short straight segments don't."""
    pts = wire.discretize(Deflection=deflection)
    if (pts[0] - pts[-1]).Length > 1e-9:
        pts.append(pts[0])
    return Part.makePolygon(pts)


def round_face_edges(shape, z, r):
    """Rounds the edges of shape's face at height z."""
    edges = [e for e in shape.Edges if all(abs(v.Point.z - z) < 1e-6 for v in e.Vertexes)]
    return shape.makeFillet(r, edges)


def board_facts(board, buttons):
    """What the case is built around, measured from the board's 3D model."""
    solids = board.Solids
    pcb = max(solids, key=lambda s: s.BoundBox.XLength * s.BoundBox.YLength)
    # the board's top surface: where the parts sit (the model's board body leaves out the copper and mask, so it
    # stops a little below the real 1.6 mm)
    top = min(s.BoundBox.ZMin for s in solids if s is not pcb and s.BoundBox.ZMin > pcb.BoundBox.ZMax - 0.2)
    # the switches' stems: the tallest things on the board
    stem = max(s.BoundBox.ZMax for s in solids)
    # the display's active area: the model's thin marker face on the top polarizer
    aa = [s for s in solids if s.BoundBox.ZLength < 0.02 and s.BoundBox.XLength > 15]
    if len(aa) != 1:
        raise SystemExit("can't find the display's active area in the board's model")
    aa = aa[0].BoundBox
    others = [s for s in solids if s is not pcb and not any(
        abs(s.BoundBox.Center.x - b["x"]) < 3 and abs(s.BoundBox.Center.y - b["y"]) < 3 for b in buttons)]
    return {"pcb": pcb, "top": top, "stem": stem, "aa": aa,
            "tallest_other": max(s.BoundBox.ZMax for s in others),
            "display_top": aa.ZMax, "bottom": pcb.BoundBox.ZMin}


def main():
    info = json.load(open(os.path.join(OUT, "board.json")))
    board = Part.Shape()
    board.read(os.path.join(OUT, "board.step"))
    f = board_facts(board, info["buttons"])
    W, H, R = info["width"], info["height"], info["corner_radius"]

    # Heights, z up from the board's bottom
    z_cap0 = f["stem"] + CAP_LIFT                      # a cap's bottom, at rest
    z_under = z_cap0 + FLANGE_T + CAP_PLAY            # the plate's underside
    z_front = z_under + PLATE                         # the front face
    z_cap_top = z_front + CAP_PROUD
    z_back = -(HOLDER_UNDER + HOLDER[2] + FLOOR)      # the back face
    z_floor = z_back + FLOOR                          # the floor's inside

    ox, oy, ow, oh, orad = -CLEAR - WALL, -CLEAR - WALL, W + 2 * (CLEAR + WALL), H + 2 * (CLEAR + WALL), R + CLEAR + WALL
    ix, iy, iw, ih, irad = -CLEAR, -CLEAR, W + 2 * CLEAR, H + 2 * CLEAR, R + CLEAR
    pads = info["battery_pads"]
    notch_y = sum(p["y"] for p in pads) / len(pads)

    # ---- the front shell ----
    front = rbox(ox, oy, ow, oh, orad, 0, z_front)
    front = round_face_edges(front, z_front, EDGE_ROUND)
    front = front.cut(rbox(ix, iy, iw, ih, irad, -1, z_under))
    for h in info["holes"]:
        post = Part.makeCylinder(POST_R, z_under - f["top"] + 0.01, V(h["x"], h["y"], f["top"]))
        front = front.fuse(post)
    for h in info["holes"]:
        top = z_front - PILOT_SKIN
        front = front.cut(Part.makeCylinder(PILOT_R, top - f["top"] + 0.1, V(h["x"], h["y"], f["top"] - 0.1)))
    caps = []
    for b in info["buttons"]:
        kind = "narrow" if b["row"] == "stacks" else "wide"
        cw, ch = CAP[kind]
        front = front.cut(cbox(b["x"], b["y"], cw + 2 * CAP_HOLE, ch + 2 * CAP_HOLE, z_under - 0.1, z_front + 0.1))
        caps.append((b, kind))
    aa = f["aa"]
    acx, acy = (aa.XMin + aa.XMax) / 2, (aa.YMin + aa.YMax) / 2
    lens_w, lens_h = aa.XLength + 2 * LENS_MARGIN, aa.YLength + 2 * LENS_MARGIN
    z_lens = z_under + LENS_T
    win0 = (aa.XLength + 2 * WINDOW_MARGIN, aa.YLength + 2 * WINDOW_MARGIN)
    win1 = (win0[0] + 2 * WINDOW_BEVEL, win0[1] + 2 * WINDOW_BEVEL)
    bevel = Part.makeLoft([rect_wire(acx, acy, win0[0], win0[1], z_lens - 0.01),
                           rect_wire(acx, acy, win1[0], win1[1], z_lens + WINDOW_BEVEL)], True)
    front = front.cut(bevel)
    front = front.cut(cbox(acx, acy, win1[0], win1[1], z_lens + WINDOW_BEVEL - 0.01, z_front + 1))
    front = front.cut(cbox(acx, acy, lens_w + 0.2, lens_h + 0.2, z_under - 0.1, z_lens))
    front = front.cut(cbox(ix - NOTCH_DEEP / 2, notch_y, NOTCH_DEEP + 0.02, NOTCH_LONG, -0.1, NOTCH_FRONT))
    # labels under the bottom row, engraved into the face; all the same size, the size that fits the longest
    bottom = [b for b in info["buttons"] if b["row"] == "bottom" and b["label"]]
    pitch = min(abs(a["x"] - c["x"]) for a in bottom for c in bottom if a is not c)
    size = LABEL_SIZE
    for _ in range(2):
        widest = 0
        for b in bottom:
            glyphs = Part.makeWireString(b["label"], os.path.dirname(FONT) + "/", os.path.basename(FONT), size, 0)
            widest = max(widest, Part.Compound([w for c in glyphs for w in c]).BoundBox.XLength)
        if widest > pitch - 1.0:
            size *= (pitch - 1.0) / widest
    label_y = bottom[0]["y"] - CAP["wide"][1] / 2 - CAP_HOLE - LABEL_GAP
    for b in bottom:
        glyphs = Part.makeWireString(b["label"], os.path.dirname(FONT) + "/", os.path.basename(FONT), size, 0)
        faces = [Part.makeFace([polygon(w) for w in c], "Part::FaceMakerBullseye") for c in glyphs if c]
        text = Part.Compound(faces)
        bb = text.BoundBox
        text.translate(V(b["x"] - (bb.XMin + bb.XMax) / 2, label_y - bb.YMax, z_front))
        front = front.cut(text.extrude(V(0, 0, -LABEL_DEPTH)))
    front = front.removeSplitter()

    # ---- the back shell ----
    back = rbox(ox, oy, ow, oh, orad, z_back, 0)
    back = round_face_edges(back, z_back, EDGE_ROUND)
    back = back.cut(rbox(ix, iy, iw, ih, irad, z_floor, 1))
    for h in info["holes"]:
        back = back.fuse(Part.makeCylinder(STANDOFF_R, -z_floor, V(h["x"], h["y"], z_floor)))
    for h in info["holes"]:
        back = back.cut(Part.makeCylinder(SCREW_R, -z_back + 0.2, V(h["x"], h["y"], z_back - 0.1)))
        back = back.cut(Part.makeCylinder(HEAD_R, -HEAD_SEAT - z_back + 0.1, V(h["x"], h["y"], z_back - 0.1)))
    hcx, hcy = W / 2, H / 2
    hw, hh = HOLDER[0] + 2 * HOLDER_CLEAR, HOLDER[1] + 2 * HOLDER_CLEAR
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = hcx + sx * (hw / 2 + CRADLE_T / 2), hcy + sy * (hh / 2 + CRADLE_T / 2)
            back = back.fuse(cbox(cx - sx * (CRADLE_LEG / 2 - CRADLE_T / 2), cy, CRADLE_LEG, CRADLE_T,
                                  z_floor - 0.01, z_floor + CRADLE_H))
            back = back.fuse(cbox(cx, cy - sy * (CRADLE_LEG / 2 - CRADLE_T / 2), CRADLE_T, CRADLE_LEG,
                                  z_floor - 0.01, z_floor + CRADLE_H))
    back = back.cut(cbox(ix - NOTCH_DEEP / 2, notch_y, NOTCH_DEEP + 0.02, NOTCH_LONG, -NOTCH_BACK, 0.1))
    back = back.removeSplitter()

    # ---- the caps ----
    def cap(kind):
        cw, ch = CAP[kind]
        fw, fh = FLANGE[kind]
        body = cbox(0, 0, cw, ch, FLANGE_T - 0.01, z_cap_top - z_cap0)
        body = round_face_edges(body, z_cap_top - z_cap0, CAP_ROUND)
        return body.fuse(cbox(0, 0, fw, fh, 0, FLANGE_T)).removeSplitter()

    cap_shapes = {k: cap(k) for k in CAP}
    placed = []
    for b, kind in caps:
        c = cap_shapes[kind].copy()
        c.translate(V(b["x"], b["y"], z_cap0))
        placed.append((b["ref"], c))

    # ---- checks ----
    problems = []

    def overlap(a, b):
        if not a.BoundBox.intersect(b.BoundBox):
            return 0.0
        return a.common(b).Volume

    parts = [s for s in board.Solids]
    for name, shape in [("front shell", front), ("back shell", back)] + [(f"cap {r}", c) for r, c in placed]:
        for s in parts:
            v = overlap(shape, s)
            if v > 1e-4:
                bb = s.BoundBox
                problems.append(f"{name} overlaps the board's model by {v:.3f} mm3 at x {bb.XMin:.1f}-{bb.XMax:.1f}, "
                                f"y {bb.YMin:.1f}-{bb.YMax:.1f}, z {bb.ZMin:.2f}-{bb.ZMax:.2f}")
    for i, (r, c) in enumerate(placed):
        if overlap(c, front) > 1e-4:
            problems.append(f"cap {r} overlaps the front shell")
        for r2, c2 in placed[i + 1:]:
            if overlap(c, c2) > 1e-4:
                problems.append(f"caps {r} and {r2} overlap")
        # pressed: moved down by the switch's travel, it must touch only its own switch's stem
        p = c.copy()
        p.translate(V(0, 0, -SWITCH_TRAVEL))
        b = next(b for b, _ in caps if b["ref"] == r)
        for s in parts:
            sb = s.BoundBox
            if abs(sb.Center.x - b["x"]) < 1 and abs(sb.Center.y - b["y"]) < 1 and sb.ZMax > f["stem"] - 0.01:
                continue                                    # its own switch's stem
            if overlap(p, s) > 1e-4:
                problems.append(f"cap {r}, pressed, hits a part other than its switch")
    if overlap(front, back) > 1e-4:
        problems.append("the shells overlap")

    if abs(f["bottom"]) > 0.01:
        problems.append(f"the board's bottom is at z {f['bottom']:.2f} in its model, not 0")
    print(f"case: board top {f['top']:.2f}, switch stems {f['stem']:.2f}, display top {f['display_top']:.2f}, "
          f"tallest part but the switches {f['tallest_other']:.2f} mm")
    print(f"case: front face {z_front:.2f}, plate underside {z_under:.2f} ({z_under - f['tallest_other']:.2f} above the tallest "
          f"part but the switches), back face {z_back:.2f}: {z_front - z_back:.1f} mm thick, "
          f"{z_cap_top - z_back:.1f} with the caps")
    print(f"case: outside: {ow:.1f} x {oh:.1f} mm; window {win0[0]:.2f} x {win0[1]:.2f} (front {win1[0]:.2f} x {win1[1]:.2f}); "
          f"clear window to cut: {lens_w:.1f} x {lens_h:.1f} x {LENS_T} mm; labels {size:.2f} mm")

    # ---- out ----
    def stl(shape, name, flip=False):
        s = shape.copy()
        if flip:
            s.rotate(V(0, 0, 0), V(1, 0, 0), 180)
        s.translate(V(0, 0, -s.BoundBox.ZMin))
        mesh = MeshPart.meshFromShape(Shape=s, LinearDeflection=0.01, AngularDeflection=0.1, Relative=False)
        mesh.write(os.path.join(OUT, name))

    stl(front, "front.stl", flip=True)
    stl(back, "back.stl")
    stl(cap_shapes["wide"], "cap_wide.stl")
    stl(cap_shapes["narrow"], "cap_narrow.stl")
    doc = App.newDocument("case")
    objs = []
    for name, shape in [("board", board), ("front", front), ("back", back)] + [(f"cap_{r}", c) for r, c in placed]:
        o = doc.addObject("Part::Feature", name)
        o.Shape = shape
        objs.append(o)
    doc.recompute()
    Part.export(objs, os.path.join(OUT, "case.step"))
    doc.saveAs(os.path.join(OUT, "case.FCStd"))
    # a cut through the middle column (stack 4, NEW and the window), for the section drawing
    sect = {}
    x = W / 2
    for name, shape in [("board", board), ("front", front), ("back", back)] + [(f"cap_{r}", c) for r, c in placed]:
        wires = shape.slice(V(1, 0, 0), x)
        sect[name] = [[(p.y, p.z) for p in w.discretize(Deflection=0.02)] for w in wires]
    with open(os.path.join(OUT, "section.json"), "w") as fh:
        json.dump({"x": x, "wires": sect}, fh)
    top = {}
    for name, shape in [("front", front)] + [(f"cap_{r}", c) for r, c in placed]:
        wires = shape.slice(V(0, 0, 1), z_front - 0.05) if name == "front" else shape.slice(V(0, 0, 1), z_front + 0.5)
        top[name] = [[(p.x, p.y) for p in w.discretize(Deflection=0.02)] for w in wires]
    for name, shape in [("labels", front)]:
        wires = shape.slice(V(0, 0, 1), z_front - LABEL_DEPTH / 2)
        top[name] = [[(p.x, p.y) for p in w.discretize(Deflection=0.02)] for w in wires]
    with open(os.path.join(OUT, "top.json"), "w") as fh:
        json.dump(top, fh)

    if problems:
        print("\n".join("case: PROBLEM: " + p for p in problems))
        sys.stdout.flush()                              # FreeCAD's exit drops unflushed output
        sys.exit(1)
    print("case: fit checks passed: nothing overlaps the board, its parts or each other; caps clear when pressed")


main()
