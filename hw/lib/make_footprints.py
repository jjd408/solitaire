#!/usr/bin/env python3
"""Writes the project's KiCad footprints into solitaire.pretty/.

Panasonic AYF531035 (Y5B series, 10 contacts at 0.5mm pitch, the LS013B7DH05's recommended FPC connector):
from Panasonic's Y5B/Y5BW datasheet ACCTB1E 202110, in ../../docs/datasheets/panasonic_y5b.pdf. Pads follow
the "Recommended PC board pattern" on page 7; the body outline follows the dimension table on page 4 (10
pins: A = 7.00 wide) and the side view (2.90 deep, 3.70 with the lever open, 1.00 high).

Orientation: viewed from the top, the FPC goes in from the bottom (+Y) edge, where the signal pads are;
the hold-down pads are toward the back. Pad 1 is on the left. With the display face up and its FPC
running straight into the connector, Sharp's FPC lead 1 lands on pad 1.
Run it again after editing the dimensions below.
"""
import os
import uuid

PINS = 10
PITCH = 0.5
PAD_W, PAD_H = 0.30, 0.80             # signal pads
MP_W, MP_H = 0.40, 0.80               # hold-down pads
MP_FROM_END = 1.00                    # hold-down pad centre to the end signal pad's centre, in X
MP_BACK = 2.50                        # hold-down pad centre behind the signal pads' centre (3.30 - 0.80)
BODY_W, BODY_D = 7.00, 2.90
LEVER_OPEN_D = 3.70
# The terminals stick out 0.30 past the body's front edge; this puts their tips 0.30 inside the pads'
# front edge. Panasonic doesn't dimension pads to body, so this is an estimate.
BODY_FRONT = PAD_H / 2 - 0.60
COURTYARD = 0.25
LINE = 0.12


def uid(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "solitaire/" + name))


def text(kind, value, x, y, layer, name, hide=False, size=1.0):
    hidden = "\n\t\t(hide yes)" if hide else ""
    return (f'\t(property "{kind}" "{value}"\n\t\t(at {x:.3f} {y:.3f} 0)\n\t\t(layer "{layer}"){hidden}\n'
            f'\t\t(uuid "{uid(name + kind)}")\n'
            f'\t\t(effects (font (size {size} {size}) (thickness {size * 0.15:.3f})))\n\t)\n')


def line(x1, y1, x2, y2, layer, width, name):
    return (f'\t(fp_line (start {x1:.3f} {y1:.3f}) (end {x2:.3f} {y2:.3f})\n'
            f'\t\t(stroke (width {width}) (type solid)) (layer "{layer}") (uuid "{uid(name)}")\n\t)\n')


def rect(x1, y1, x2, y2, layer, width, name):
    return (f'\t(fp_rect (start {x1:.3f} {y1:.3f}) (end {x2:.3f} {y2:.3f})\n'
            f'\t\t(stroke (width {width}) (type solid)) (fill no) (layer "{layer}") (uuid "{uid(name)}")\n\t)\n')


def pad(number, x, y, w, h, name):
    return (f'\t(pad "{number}" smd roundrect (at {x:.3f} {y:.3f}) (size {w:.2f} {h:.2f})\n'
            f'\t\t(layers "F.Cu" "F.Paste" "F.Mask") (roundrect_rratio 0.25) (uuid "{uid(name)}")\n\t)\n')


def ayf531035():
    name = "Panasonic_AYF531035_1x10-1MP_P0.5mm_Horizontal"
    first = -(PINS - 1) * PITCH / 2
    mp_x = -first + MP_FROM_END
    body_l, body_r = -BODY_W / 2, BODY_W / 2
    body_back = BODY_FRONT - BODY_D
    cy_top = BODY_FRONT - LEVER_OPEN_D - COURTYARD
    cy_bot = PAD_H / 2 + COURTYARD
    cx = max(BODY_W / 2, mp_x + MP_W / 2) + COURTYARD

    s = (f'(footprint "{name}"\n\t(version 20241229)\n\t(generator "make_footprints.py")\n'
         '\t(generator_version "9.0")\n\t(layer "F.Cu")\n')
    s += text("Reference", "REF**", 0, cy_top - 1.0, "F.SilkS", name)
    s += text("Value", name, 0, cy_bot + 1.0, "F.Fab", name)
    s += text("Datasheet", "https://industrial.panasonic.com/ww/products/pt/fpc-ffc-connectors/models/AYF531035",
              0, 0, "F.Fab", name, hide=True)
    s += text("Description", "Panasonic Y5B FPC connector, 10 contacts top and bottom, 0.5mm pitch, 1.0mm high, "
              "back-flip lock", 0, 0, "F.Fab", name, hide=True)
    s += '\t(attr smd)\n'

    # Fab: the body, a pin 1 chamfer, and which edge the FPC goes in.
    ch = 0.5
    s += line(body_l + ch, BODY_FRONT, body_r, BODY_FRONT, "F.Fab", 0.1, name + "fab1")
    s += line(body_r, BODY_FRONT, body_r, body_back, "F.Fab", 0.1, name + "fab2")
    s += line(body_r, body_back, body_l, body_back, "F.Fab", 0.1, name + "fab3")
    s += line(body_l, body_back, body_l, BODY_FRONT - ch, "F.Fab", 0.1, name + "fab4")
    s += line(body_l, BODY_FRONT - ch, body_l + ch, BODY_FRONT, "F.Fab", 0.1, name + "fab5")
    s += (f'\t(fp_text user "FPC" (at 0 {cy_bot + 2.2:.3f} 0) (layer "F.Fab") (uuid "{uid(name + "fpc")}")\n'
          '\t\t(effects (font (size 0.8 0.8) (thickness 0.12)))\n\t)\n')
    s += (f'\t(fp_text user "${{REFERENCE}}" (at 0 {(BODY_FRONT + body_back) / 2:.3f} 0) (layer "F.Fab") '
          f'(uuid "{uid(name + "fabref")}")\n\t\t(effects (font (size 0.8 0.8) (thickness 0.12)))\n\t)\n')

    # Silkscreen: the body's sides and back, clear of the pads, and a pin 1 mark.
    gap = 0.2
    sx = body_r + LINE
    s += line(-sx, body_back - LINE, sx, body_back - LINE, "F.SilkS", LINE, name + "silk_back")
    for side, sign in (("l", -1), ("r", 1)):
        s += line(sign * sx, body_back - LINE, sign * sx, -MP_BACK - MP_H / 2 - gap, "F.SilkS", LINE,
                  name + "silk_" + side + "1")
        s += line(sign * sx, -MP_BACK + MP_H / 2 + gap, sign * sx, BODY_FRONT, "F.SilkS", LINE,
                  name + "silk_" + side + "2")
    s += line(first - PAD_W / 2 - 0.3, PAD_H / 2, first - PAD_W / 2 - 0.3, PAD_H / 2 + 0.5, "F.SilkS", LINE,
              name + "pin1")

    s += rect(-cx, cy_top, cx, cy_bot, "F.CrtYd", 0.05, name + "crtyd")

    for i in range(PINS):
        s += pad(i + 1, first + i * PITCH, 0, PAD_W, PAD_H, f"{name}pad{i + 1}")
    s += pad("MP", -mp_x, -MP_BACK, MP_W, MP_H, name + "mp_l")
    s += pad("MP", mp_x, -MP_BACK, MP_W, MP_H, name + "mp_r")
    s += '\t(embedded_fonts no)\n)\n'
    return name, s


def dfe201612e():
    """Murata DFE201612E (2.0 x 1.6 x 1.2mm metal-alloy power inductor), the TPS63900's inductor.

    Pads from the "Recommended PCB pattern" in Murata's reference specification for the 2016-size DFE201612P
    (spec J(E)TE243A-9101D-01), which shares the DFE201612E's body: two 0.8 x 1.8 pads, 0.8 apart. KiCad's
    L_Murata_DFE201610P has smaller pads (0.55 x 1.6, 2.0 overall), so it isn't used. The 3D model is KiCad's
    CKCS201610 model (the same 2.0 x 1.6 body, 1.0 high) stretched to 1.2mm; KiCad
    doesn't ship a model for its own DFE201610P footprint.
    """
    name = "L_Murata_DFE201612E"
    pad_w, pad_h, gap = 0.8, 1.8, 0.8
    body_l, body_w = 2.0, 1.6
    px = (gap + pad_w) / 2
    cx, cy = px + pad_w / 2 + COURTYARD, max(pad_h, body_w) / 2 + COURTYARD

    s = (f'(footprint "{name}"\n\t(version 20241229)\n\t(generator "make_footprints.py")\n'
         '\t(generator_version "9.0")\n\t(layer "F.Cu")\n')
    s += text("Reference", "REF**", 0, -cy - 1.0, "F.SilkS", name)
    s += text("Value", name, 0, cy + 1.0, "F.Fab", name)
    s += text("Datasheet", "https://www.murata.com/en/products/productdetail?partno=DFE201612E-2R2M%23",
              0, 0, "F.Fab", name, hide=True)
    s += text("Description", "Murata DFE201612E metal-alloy power inductor, 2.0x1.6x1.2mm (0806)", 0, 0, "F.Fab",
              name, hide=True)
    s += '\t(attr smd)\n'
    s += rect(-body_l / 2, -body_w / 2, body_l / 2, body_w / 2, "F.Fab", 0.1, name + "fab")
    s += (f'\t(fp_text user "${{REFERENCE}}" (at 0 0 0) (layer "F.Fab") (uuid "{uid(name + "fabref")}")\n'
          '\t\t(effects (font (size 0.5 0.5) (thickness 0.08)))\n\t)\n')
    # Silkscreen above and below the body, between the pads.
    sy = pad_h / 2 + LINE
    for side, sign in (("t", -1), ("b", 1)):
        s += line(-gap / 2 + 0.15, sign * sy, gap / 2 - 0.15, sign * sy, "F.SilkS", LINE, name + "silk" + side)
    s += rect(-cx, -cy, cx, cy, "F.CrtYd", 0.05, name + "crtyd")
    s += pad(1, -px, 0, pad_w, pad_h, name + "pad1")
    s += pad(2, px, 0, pad_w, pad_h, name + "pad2")
    s += ('\t(embedded_fonts no)\n'
          '\t(model "${KICAD9_3DMODEL_DIR}/Inductor_SMD.3dshapes/L_Cenker_CKCS201610.step"\n'
          '\t\t(offset (xyz 0 0 0)) (scale (xyz 1 1 1.2)) (rotate (xyz 0 0 0))\n\t)\n)\n')
    return name, s


def skrpace010():
    """ALPS SKRPACE010 (4.2 x 3.2 x 2.5mm top-push tact switch), the game's buttons.

    Pads from the PC board land drawing in ALPS's SKRP datasheet (../../docs/datasheets/alps_skrp.pdf), viewed
    from the switch's mounting face: four 1.05 x 0.65 pads, 3.1 apart inside and 5.2 outside in X, 1.5 apart
    inside and 2.8 outside in Y. ALPS's terminals 1 and 2 (the top pair) are joined inside the switch, as are
    3 and 4, so the pads are numbered 1, 1, 2, 2 to suit a two-pin push-button symbol.
    """
    name = "SW_Alps_SKRPACE010"
    pad_w, pad_h = (5.2 - 3.1) / 2, (2.8 - 1.5) / 2
    px, py = (3.1 + pad_w) / 2, (1.5 + pad_h) / 2
    body_w, body_h = 4.2, 3.2
    cx, cy = px + pad_w / 2 + COURTYARD, body_h / 2 + COURTYARD

    s = (f'(footprint "{name}"\n\t(version 20241229)\n\t(generator "make_footprints.py")\n'
         '\t(generator_version "9.0")\n\t(layer "F.Cu")\n')
    s += text("Reference", "REF**", 0, -cy - 1.0, "F.SilkS", name)
    s += text("Value", name, 0, cy + 1.0, "F.Fab", name)
    s += text("Datasheet", "https://tech.alpsalpine.com/e/products/detail/SKRPACE010/", 0, 0, "F.Fab", name, hide=True)
    s += text("Description", "ALPS SKRP tact switch, 4.2x3.2x2.5mm, 2.55N, top push", 0, 0, "F.Fab", name, hide=True)
    s += '\t(attr smd)\n'
    s += rect(-body_w / 2, -body_h / 2, body_w / 2, body_h / 2, "F.Fab", 0.1, name + "fab")
    # The stem: 3.0 x 2.2 with R1.1 ends, drawn as its bounding box.
    s += rect(-1.5, -1.1, 1.5, 1.1, "F.Fab", 0.1, name + "stem")
    s += (f'\t(fp_text user "${{REFERENCE}}" (at 0 0 0) (layer "F.Fab") (uuid "{uid(name + "fabref")}")\n'
          '\t\t(effects (font (size 0.6 0.6) (thickness 0.09)))\n\t)\n')
    # Silkscreen along the top and bottom edges, between the pads.
    sy = body_h / 2 + LINE
    for side, sign in (("t", -1), ("b", 1)):
        s += line(-(px - pad_w / 2 - 0.2), sign * sy, px - pad_w / 2 - 0.2, sign * sy, "F.SilkS", LINE,
                  name + "silk" + side)
    s += rect(-cx, -cy, cx, cy, "F.CrtYd", 0.05, name + "crtyd")
    s += pad(1, -px, -py, pad_w, pad_h, name + "pad1a")
    s += pad(1, px, -py, pad_w, pad_h, name + "pad1b")
    s += pad(2, -px, py, pad_w, pad_h, name + "pad2a")
    s += pad(2, px, py, pad_w, pad_h, name + "pad2b")
    s += ('\t(embedded_fonts no)\n'
          '\t(model "${KIPRJMOD}/../lib/3d/SW_Alps_SKRPACE010.step"\n'
          '\t\t(offset (xyz 0 0 0)) (scale (xyz 1 1 1)) (rotate (xyz 0 0 0))\n\t)\n)\n')
    return name, s


def ls013b7dh05_outline():
    """Where the Sharp LS013B7DH05 lies on the board: its glass and FPC, as a board-only footprint (no pads,
    not in the BOM or placement files) that keeps parts out from under them and carries the display's 3D model.

    The origin is the glass's bottom-left corner, the 3D model's origin (see make_lcd_model.py); the FPC runs
    down (+Y) from the glass's bottom edge. Glass 24.68 x 30.0, FPC 9.47 wide and 13.63 long, centred on the
    glass (Sharp's spec LD-26912A). Lying face up with the FPC straight into an AYF531035 turned to face the
    glass, the connector's pad row is FPC_IN mm short of the FPC's end; the courtyard stops at the connector's.
    """
    name = "LCD_Sharp_LS013B7DH05_Outline"
    gw, gh, fw, fl = 24.68, 30.0, 9.47, 13.63
    fpc_in = 2.63                       # FPC end past the connector's pad row (estimate; see ../README.md)
    conn = fl - fpc_in                  # the connector's pad row, below the glass
    fx0, fx1 = gw / 2 - fw / 2, gw / 2 + fw / 2
    m = COURTYARD
    s = (f'(footprint "{name}"\n\t(version 20241229)\n\t(generator "make_footprints.py")\n'
         '\t(generator_version "9.0")\n\t(layer "F.Cu")\n')
    s += text("Reference", "REF**", gw / 2, -gh / 2, "F.Fab", name)
    s += text("Value", name, gw / 2, -gh / 2 + 1.5, "F.Fab", name, size=0.8)
    s += text("Datasheet", "${KIPRJMOD}/../../docs/datasheets/LS013B7DH05_spec.pdf", 0, 0, "F.Fab", name,
              hide=True)
    s += text("Description", "Sharp LS013B7DH05 memory LCD: glass and FPC outline, face up, FPC straight down",
              0, 0, "F.Fab", name, hide=True)
    s += '\t(attr board_only exclude_from_pos_files exclude_from_bom)\n'
    s += rect(0, -gh, gw, 0, "F.Fab", 0.1, name + "glass")
    s += rect(fx0, 0, fx1, fl, "F.Fab", 0.1, name + "fpc")
    s += (f'\t(fp_text user "FPC" (at {gw / 2:.3f} {fl / 2:.3f} 0) (layer "F.Fab") (uuid "{uid(name + "fpct")}")\n'
          '\t\t(effects (font (size 0.8 0.8) (thickness 0.12)))\n\t)\n')
    # silkscreen corner marks just outside the glass, to line it up by
    for (cx, cy, dx, dy) in [(0, -gh, 1, 1), (gw, -gh, -1, 1), (0, 0, 1, -1), (gw, 0, -1, -1)]:
        x, y = cx - 0.2 * dx, cy - 0.2 * dy
        s += line(x, y, x + 1.5 * dx, y, "F.SilkS", LINE, name + f"silk{cx}{cy}h")
        s += line(x, y, x, y + 1.5 * dy, "F.SilkS", LINE, name + f"silk{cx}{cy}v")
    pts = [(-m, -gh - m), (gw + m, -gh - m), (gw + m, m), (fx1, m), (fx1, conn - 0.65), (fx0, conn - 0.65),
           (fx0, m), (-m, m)]
    s += ('\t(fp_poly (pts ' + ' '.join(f'(xy {x:.3f} {y:.3f})' for x, y in pts) + ')\n'
          f'\t\t(stroke (width 0.05) (type solid)) (fill no) (layer "F.CrtYd") (uuid "{uid(name + "crtyd")}")\n\t)\n')
    s += ('\t(embedded_fonts no)\n'
          '\t(model "${KIPRJMOD}/../lib/3d/LS013B7DH05.step"\n'
          '\t\t(offset (xyz 0 0 0.05)) (scale (xyz 1 1 1)) (rotate (xyz 0 0 0))\n\t)\n)\n')
    return name, s


def main():
    os.makedirs("solitaire.pretty", exist_ok=True)
    for make in (ayf531035, dfe201612e, skrpace010, ls013b7dh05_outline):
        name, s = make()
        with open(os.path.join("solitaire.pretty", name + ".kicad_mod"), "w") as f:
            f.write(s)


if __name__ == "__main__":
    main()
