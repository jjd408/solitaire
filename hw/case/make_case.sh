#!/bin/sh
# Makes the case's print files in out/, from the board (../sol/sol.kicad_pcb): see case.py.
#
#   sh make_case.sh
#
# Needs KiCad (kicad-cli and its Python, for the board) and FreeCAD (freecadcmd, for the case).
set -e
cd "$(dirname "$0")"
mkdir -p out
python3 board_info.py
# the board's 3D model with every part but J3, the programming header, which is left off
refs=$(python3 -c "
import pcbnew
b = pcbnew.LoadBoard('../sol/sol.kicad_pcb')
print(','.join(f.GetReference() for f in b.GetFootprints() if f.GetReference() != 'J3'))")
kicad-cli pcb export step --drill-origin --subst-models --component-filter "$refs" -f -o out/board.step \
    ../sol/sol.kicad_pcb >/dev/null
# FreeCAD's command line exits 0 even when the script fails, so case.py's last line says how it went
freecadcmd case.py >out/case.log 2>&1 || true
grep -e '^case: ' -e 'Exception' -e 'Error' out/case.log | sed 's/^case: //'
grep -q '^case: fit checks passed' out/case.log
