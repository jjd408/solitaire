"""Draws the case from case.py's outlines: out/case-front.png (the front face, caps and labels) and
out/case-section.png (a cut through the middle column, front up: caps, plate, window, board, back).

    python3 draw.py
"""
import json
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Polygon  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
COLORS = {"front": "#c9ccd1", "back": "#9aa0a8", "board": "#3f7d4f", "cap": "#f2efe6", "labels": "#55595f"}


def color(name):
    return COLORS.get(name.split("_")[0], "#888888")


def fill(ax, wires, c, z=1, edge="#222222", lw=0.4):
    # outlines with holes: draw the biggest first, then the holes in white over it, smallest last
    wires = sorted(wires, key=lambda w: -area(w))
    for i, w in enumerate(wires):
        if len(w) < 3:
            continue
        inner = any(contains(o, w[0]) for o in wires[:i])
        ax.add_patch(Polygon(w, closed=True, facecolor="white" if inner else c, edgecolor=edge, lw=lw,
                             zorder=z + i * 0.001))


def area(w):
    return abs(sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(w, w[1:] + w[:1]))) / 2


def contains(poly, p):
    x, y = p
    inside = False
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            inside = not inside
    return inside


def front():
    top = json.load(open(os.path.join(OUT, "top.json")))
    fig, ax = plt.subplots(figsize=(5.2, 6.2), dpi=160)
    fill(ax, top["front"], COLORS["front"])
    for name, wires in top.items():
        if name.startswith("cap"):
            fill(ax, wires, COLORS["cap"], z=3)
    letters = sorted((w for w in top["labels"] if area(w) < 3), key=lambda w: -area(w))  # cut at half depth
    for i, w in enumerate(letters):
        hole = any(contains(o, w[0]) for o in letters[:i])    # the inside of an O, D, P...
        ax.add_patch(Polygon(w, closed=True, facecolor=COLORS["front"] if hole else COLORS["labels"],
                             edgecolor="none", zorder=4 + i * 0.001))
    ax.set_aspect("equal")
    ax.autoscale_view()
    ax.set_title("Front: 69 x 85 mm", fontsize=9)
    ax.tick_params(labelsize=6)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "case-front.png"))


def section():
    sect = json.load(open(os.path.join(OUT, "section.json")))
    fig, ax = plt.subplots(figsize=(9, 4.2), dpi=160)
    for name, wires in sect["wires"].items():
        for w in wires:
            if len(w) >= 3:
                ax.add_patch(Polygon(w, closed=True, facecolor=color(name), edgecolor="#222222", lw=0.3,
                                     zorder=2 if name == "board" else 1))
    ax.set_aspect("equal")
    ax.autoscale_view()
    ax.set_xlabel("y (mm)", fontsize=7)
    ax.set_ylabel("z (mm)", fontsize=7)
    ax.tick_params(labelsize=6)
    ax.set_title(f"Cut at x = {sect['x']:g} mm (stack 4, NEW and the window), front up: "
                 "front shell, caps, board and parts, back shell", fontsize=8)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "case-section.png"))


front()
section()
print("case-front.png, case-section.png")
