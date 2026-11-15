#!/bin/sh
# Makes the files to order the board from sol.kicad_pcb and sol.kicad_sch, in fab/ (board-house-neutral formats):
#
#   fab/gerbers/            Gerbers (copper, mask, paste, silkscreen, outline) and Excellon drill files
#   fab/sol-gerbers.zip     the same, zipped, for uploading
#   fab/sol-bom.csv         the parts list from the schematic: references, value, manufacturer, part number
#   fab/sol-cpl.csv         where each part sits (centre, rotation, side), for assembly
#   fab/sol-assembly.pdf    the assembly drawing: outline, parts and their references (the fabrication layer)
#   fab/jlc-bom.csv         the BOM in JLCPCB's format: Comment, Designator, Footprint, LCSC Part # (from the
#                           schematic's LCSC fields)
#   fab/jlc-cpl.csv         the placement file in JLCPCB's format: Designator, Mid X, Mid Y, Layer, Rotation
#
#   sh make_fab.sh
#
# Coordinates are measured from the board's bottom-left corner (its drill/place origin, set by layout.py).
# It checks the board first (DRC with schematic parity) and stops if anything is wrong.
set -e
cd "$(dirname "$0")"
out=fab
rm -rf "$out"
mkdir -p "$out/gerbers"

echo "checking the board..."
kicad-cli pcb drc --schematic-parity --severity-all --exit-code-violations --format json -o "$out/drc.json" \
    sol.kicad_pcb >/dev/null || { echo "DRC found problems: see $out/drc.json"; exit 1; }

echo "Gerbers and drill files..."
kicad-cli pcb export gerbers -o "$out/gerbers/" \
    --layers F.Cu,B.Cu,F.Mask,B.Mask,F.Paste,F.Silkscreen,B.Silkscreen,Edge.Cuts \
    --subtract-soldermask --no-x2 --use-drill-file-origin sol.kicad_pcb >/dev/null
kicad-cli pcb export drill -o "$out/gerbers/" --format excellon --excellon-separate-th --drill-origin plot \
    --generate-map --map-format gerberx2 sol.kicad_pcb >/dev/null
(cd "$out/gerbers" && zip -q ../sol-gerbers.zip ./*)

echo "BOM..."
kicad-cli sch export bom -o "$out/sol-bom.csv" \
    --fields 'Reference,Value,Manufacturer,MPN,Footprint,${QUANTITY},Function' \
    --labels 'References,Value,Manufacturer,Part number,Footprint,Quantity,Function' \
    --group-by 'Value,MPN,Footprint' --exclude-dnp sol.kicad_sch >/dev/null

echo "placement..."
kicad-cli pcb export pos -o "$out/sol-cpl.csv" --format csv --units mm --side front --exclude-dnp \
    --use-drill-file-origin \
    sol.kicad_pcb >/dev/null

echo "JLCPCB BOM and placement..."
kicad-cli sch export bom -o "$out/jlc-bom.csv" \
    --fields 'Value,Reference,Footprint,LCSC' --labels 'Comment,Designator,Footprint,LCSC Part #' \
    --group-by 'Value,LCSC,Footprint' --exclude-dnp sol.kicad_sch >/dev/null
python3 - "$out/sol-cpl.csv" "$out/jlc-cpl.csv" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1])))
with open(sys.argv[2], "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
    for r in rows:
        w.writerow([r["Ref"], f"{float(r['PosX']):.3f}mm", f"{float(r['PosY']):.3f}mm",
                    "Top" if r["Side"] == "top" else "Bottom", f"{float(r['Rot']):.0f}"])
PY
python3 - "$out/jlc-bom.csv" <<'PY'
# JLCPCB wants each designator listed (SW1,SW2,...), not KiCad's ranges (SW1-SW16); and DS1's value names the
# display, but what JLCPCB fits there is its connector
import csv, re, sys
rows = list(csv.reader(open(sys.argv[1])))
def expand(refs):
    out = []
    for part in refs.split(","):
        m = re.fullmatch(r"([A-Z]+)(\d+)-[A-Z]+(\d+)", part.strip())
        out += [f"{m[1]}{n}" for n in range(int(m[2]), int(m[3]) + 1)] if m else [part.strip()]
    return ",".join(out)
for r in rows[1:]:
    r[1] = expand(r[1])
    if r[1] == "DS1":
        r[0] = "AYF531035 FPC connector (for the LS013B7DH05 display)"
with open(sys.argv[1], "w", newline="") as f:
    csv.writer(f, quoting=csv.QUOTE_ALL).writerows(rows)
PY
missing=$(awk -F'","' 'NR > 1 && $4 ~ /^"?$/ { print $2 }' "$out/jlc-bom.csv")
[ -z "$missing" ] || echo "WARNING: no LCSC part number for: $missing"

echo "assembly drawing..."
# the fabrication layer with the parts' values hidden, so the references read clearly; drawn at the board's size
python3 - "$out/asm.kicad_pcb" <<'PY'
import sys, pcbnew
b = pcbnew.LoadBoard("sol.kicad_pcb")
for f in b.GetFootprints():
    f.Value().SetVisible(False)
b.Save(sys.argv[1])
PY
kicad-cli pcb export svg -o "$out/asm.svg" --layers F.Fab,Edge.Cuts --exclude-drawing-sheet --page-size-mode 2 \
    --black-and-white "$out/asm.kicad_pcb" >/dev/null
rsvg-convert -f pdf -b white -o "$out/sol-assembly.pdf" "$out/asm.svg"
rm -f "$out/asm.kicad_pcb" "$out/asm.svg" "$out"/asm.kicad_p*

rm -f "$out/drc.json"
echo "done: $out/"
ls -1 "$out"
