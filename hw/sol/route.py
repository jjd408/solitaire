#!/usr/bin/env python3
"""Routes the Solitaire board (run after layout.py, from this folder, with KiCad's Python).

A small maze router: A* on a 0.05 mm grid over both copper layers, with 45-degree moves and costs for turns,
vias and the back layer (kept mostly for the ground plane).

Fixed copper (pads, the mounting holes, the board edge) is a hard limit with exact clearances: for every grid
point and layer the router keeps the distance to the nearest copper, its net, and the distance to the nearest
copper of any other net, so a track of half-width h may use a point when other nets' copper is at least
clearance + h away. Power tracks are 0.3 mm and narrow to 0.2 mm only where they must (at fine-pitch pads).
Beyond each used pin of the MCU and the display connector a short corridor is kept for that pin's net, so no
track can box a pin in.

Tracks are placed by negotiation (PathFinder): every net is routed with the other nets' tracks as a cost
rather than an obstacle, and the nets that overlap are ripped up and routed again with the cost of sharing
raised and a lasting cost added where they fought, until nothing overlaps. Ground then gets a via beside
every surface-mount ground pad, stitching vias, and a pour on both layers. Rerunning replaces all tracks,
vias and zones.
"""
import heapq
import math
import os
import sys
import time

import numpy as np
import pcbnew

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from layout import OX, OY, W, H, R, HOLES, PCB  # noqa: E402

G = 0.1                        # grid step, mm (pad centres fall on it)
CLR = 0.2                      # copper clearance
EDGE = 0.5                     # copper to board edge
VIA_D, VIA_DRILL = 0.6, 0.3
VIA_SPACING = 0.9              # via centre to via centre, any nets
NARROW = 0.2                   # signal width, and the width power tracks narrow to
POWER = {"+3V0": 0.3, "/VBAT": 0.3, "GND": 0.3, "Net-(U2-LX1)": 0.3, "Net-(U2-LX2)": 0.3}
HMAX = 0.15                    # the widest track's half-width
EPS = 0.01                     # allowance for the grid (a diagonal step's midpoint can be ~0.005 closer)

BACK_COST = 1.8                # the back layer is the ground plane: use it to cross, not to run along
VIA_COST = 7.0                 # in grid steps (0.7 mm of track)
TURN_COST = {0: 0.0, 1: 0.4, 2: 1.5}
NARROW_COST = 2.0              # a power track's step at narrow width costs this much more
DIAG = 1.6                     # a diagonal step (1.414 long): a little dearer, for straighter tracks
HWEIGHT = 1.4                  # weight on the distance estimate (1 = optimal paths, slower)
PRES0, PRES_GROW = 1.0, 1.8    # cost of a step that crowds another net's track, and its growth per pass
HIST = 0.3                     # lasting cost added per pass to points two nets fought over
PASSES = 30
STUCK = 5                      # stop when the same nets still crowd each other this many passes running

# Ground vias placed before routing, where the tracks would otherwise leave none
GND_VIAS = []
# Ground connections routed like signals rather than left to the pour, where the other tracks could wall the
# pour off: the MCU's decoupling capacitors' ground pads to its DVSS pin.
LOCAL = {"GND:U1": [("U1", "11"), ("C6", "2"), ("C8", "2")]}

# Fine-pitch parts whose used pins get an escape corridor this long (mm) beyond the pad
ESCAPE = {"U1": 1.2, "DS1": 1.0}

NETS = ["Net-(U2-LX1)", "Net-(U2-LX2)", "Net-(U2-CFG1)", "Net-(U2-CFG2)", "Net-(U2-CFG3)", "/VBAT",
        "Net-(DS1-SCLK)", "Net-(DS1-SI)", "Net-(DS1-SCS)", "Net-(DS1-EXTCOMIN)", "Net-(DS1-DISP)", "+3V0",
        "/RST", "Net-(J3-TEST{slash}SBWTCK)"]
NETS += ["Net-(U1-P3.0{slash}MCLK)", "Net-(U1-P3.1{slash}OA2O)", "Net-(U1-P3.2{slash}OA2-)"]
NETS += list(LOCAL)
NETS += [f"stacks{i}" for i in range(1, 10)] + [f"suits{i}" for i in range(1, 5)]

NX, NY = int(round(W / G)) + 1, int(round(H / G)) + 1
DIRS = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
XS = np.arange(NX) * G
YS = np.arange(NY) * G


def to_mm(v):
    return pcbnew.ToMM(v.x) - OX, pcbnew.ToMM(v.y) - OY


def kpt(x, y):
    return pcbnew.VECTOR2I(pcbnew.FromMM(OX + x), pcbnew.FromMM(OY + y))


def window(x0, y0, x1, y1, reach):
    i0, i1 = max(0, int((x0 - reach) / G)), min(NX, int((x1 + reach) / G) + 2)
    j0, j1 = max(0, int((y0 - reach) / G)), min(NY, int((y1 + reach) / G) + 2)
    return np.s_[j0:j1, i0:i1], XS[i0:i1][None, :], YS[j0:j1][:, None]


def seg_distance(x, y, x1, y1, x2, y2):
    vx, vy = x2 - x1, y2 - y1
    ll = vx * vx + vy * vy
    t = np.clip(((x - x1) * vx + (y - y1) * vy) / ll, 0, 1) if ll > 0 else 0
    return np.hypot(x - (x1 + t * vx), y - (y1 + t * vy))


class Field:
    """Per layer and grid point: nearest copper distance d1 and its net n1; d2, nearest copper of another net."""

    REACH = 1.0                # distances beyond this don't matter to any rule

    def __init__(self):
        self.d1 = np.full((2, NY, NX), np.inf, np.float32)
        self.n1 = np.full((2, NY, NX), -1, np.int32)
        self.d2 = np.full((2, NY, NX), np.inf, np.float32)
        self.pad = np.zeros((2, NY, NX), bool)

    def update(self, layer, sl, d, net):
        D1, N1, D2 = self.d1[layer][sl], self.n1[layer][sl], self.d2[layer][sl]
        same = N1 == net
        closer = ~same & (d < D1)
        farther = ~same & ~closer
        D2[closer] = D1[closer]
        D1[closer] = d[closer]
        N1[closer] = net
        D1[same] = np.minimum(D1[same], d[same])
        D2[farther] = np.minimum(D2[farther], d[farther])

    def rect(self, layers, cx, cy, hw, hh, net, pad=False):
        sl, x, y = window(cx - hw, cy - hh, cx + hw, cy + hh, self.REACH)
        d = np.hypot(np.maximum(np.abs(x - cx) - hw, 0), np.maximum(np.abs(y - cy) - hh, 0)).astype(np.float32)
        for L in layers:
            self.update(L, sl, d, net)
            if pad:
                self.pad[L][sl] |= d <= 0

    def circle(self, layers, cx, cy, r, net, pad=False):
        sl, x, y = window(cx - r, cy - r, cx + r, cy + r, self.REACH)
        d = np.maximum(np.hypot(x - cx, y - cy) - r, 0).astype(np.float32)
        for L in layers:
            self.update(L, sl, d, net)
            if pad:
                self.pad[L][sl] |= d <= 0

    def segment(self, layer, x1, y1, x2, y2, hw, net):
        sl, x, y = window(min(x1, x2) - hw, min(y1, y2) - hw, max(x1, x2) + hw, max(y1, y2) + hw, self.REACH)
        d = np.maximum(seg_distance(x, y, x1, y1, x2, y2) - hw, 0).astype(np.float32)
        self.update(layer, sl, d, net)

    def other(self, layer, net):
        """Distance to the nearest copper not of `net`."""
        return np.where(self.n1[layer] == net, self.d2[layer], self.d1[layer])


class Occupancy:
    """How many nets' tracks and vias crowd each grid point: `track` counts those too close for any track's
    centre to pass there, `via` those too close for a via. Conservative: it assumes the widest track."""

    def __init__(self):
        self.track = np.zeros((2, NY, NX), np.int16)
        self.via = np.zeros((2, NY, NX), np.int16)
        self.hist = np.zeros((2, NY, NX), np.float32)

    @staticmethod
    def marks(obj):
        """(layer, slice, track mask, via mask) for a routed object."""
        out = []
        if obj[0] == "t":
            _, L, x1, y1, x2, y2, w = obj
            rt, rv = CLR + w / 2 + HMAX + EPS, CLR + w / 2 + VIA_D / 2 + EPS
            sl, x, y = window(min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2), rv)
            d = seg_distance(x, y, x1, y1, x2, y2)
            out.append((L, sl, d < rt, d < rv))
        else:
            _, x, y = obj
            rt, rv = CLR + VIA_D / 2 + HMAX + EPS, CLR + VIA_D + EPS
            sl, xx, yy = window(x, y, x, y, rv)
            d = np.hypot(xx - x, yy - y)
            for L in (0, 1):
                out.append((L, sl, d < rt, d < rv))
        return out

    def add(self, marks, sign):
        for L, sl, mt, mv in marks:
            self.track[L][sl] += sign * mt
            self.via[L][sl] += sign * mv


def edge_distance():
    x, y = XS[None, :], YS[:, None]
    d = np.minimum(np.minimum(x, W - x), np.minimum(y, H - y))
    for cx, cy in [(R, R), (W - R, R), (R, H - R), (W - R, H - R)]:
        corner = ((x - cx) * np.sign(cx - W / 2) > 0) & ((y - cy) * np.sign(cy - H / 2) > 0)
        d = np.where(corner, R - np.hypot(x - cx, y - cy), d)
    return d


class Board:
    def __init__(self):
        self.board = pcbnew.LoadBoard(PCB)
        for t in list(self.board.GetTracks()):
            self.board.Delete(t)
        for z in list(self.board.Zones()):
            self.board.Delete(z)
        self.nets = {}             # name -> id
        self.pads = {}             # net name -> list of pads (dicts)
        self.field = Field()       # fixed copper only, until the tracks are final
        self.edge = edge_distance()
        self.occ = Occupancy()
        self.routes = {}           # net -> dict(objs, marks, cells)
        lone = -10
        centres = {}
        self.holes = []            # plated pad holes: (x, y, radius)
        for fp in self.board.GetFootprints():
            centres[fp.GetReference()] = to_mm(fp.GetBoundingBox(False, False).GetCenter())
            for p in fp.Pads():
                name = p.GetNetname()
                if name:
                    net = self.nets.setdefault(name, len(self.nets))
                else:
                    net, lone = lone, lone - 1      # no net: in everyone's way
                x, y = to_mm(p.GetPosition())
                bb = p.GetBoundingBox()
                hw, hh = pcbnew.ToMM(bb.GetWidth()) / 2, pcbnew.ToMM(bb.GetHeight()) / 2
                layers = [L for L, kl in ((0, pcbnew.F_Cu), (1, pcbnew.B_Cu)) if p.IsOnLayer(kl)]
                if not layers:
                    continue
                if p.GetDrillSize().x > 0:
                    self.holes.append((x, y, pcbnew.ToMM(p.GetDrillSize().x) / 2))
                circle = p.GetShape() == pcbnew.PAD_SHAPE_CIRCLE
                if circle:
                    self.field.circle(layers, x, y, hw, net, pad=True)
                else:
                    self.field.rect(layers, x, y, hw, hh, net, pad=True)
                if name:
                    self.pads.setdefault(name, []).append(dict(
                        ref=fp.GetReference(), num=p.GetNumber(), x=x, y=y, hw=hw, hh=hh, layers=layers,
                        circle=circle, smd=p.GetAttribute() == pcbnew.PAD_ATTRIB_SMD))
        self.escapes(centres)
        for i, (x, y) in enumerate(HOLES):
            self.field.circle([0, 1], x, y, 1.1 + 0.05, -100 - i)
        for x, y in GND_VIAS:
            self.field.circle([0, 1], x, y, VIA_D / 2, self.nets["GND"])
        self.static = {}           # net -> (narrow, wide, via) masks against the fixed copper

    def escapes(self, centres):
        """Keeps a corridor clear beyond each used pin of the fine-pitch parts, so that no other net's track
        can box a pin in: the corridor counts as its net's copper (nothing is drawn there)."""
        for net, pads in self.pads.items():
            if net.startswith("unconnected-"):
                continue
            for p in pads:
                if p["ref"] not in ESCAPE:
                    continue
                cx, cy = centres[p["ref"]]
                n = ESCAPE[p["ref"]]
                if p["hw"] > p["hh"]:                     # out along the pad's long side
                    s = 1 if p["x"] > cx else -1
                    x0 = p["x"] + s * p["hw"]
                    self.field.rect(p["layers"], x0 + s * n / 2, p["y"], n / 2, p["hh"], self.nets[net])
                else:
                    s = 1 if p["y"] > cy else -1
                    y0 = p["y"] + s * p["hh"]
                    self.field.rect(p["layers"], p["x"], y0 + s * n / 2, p["hw"], n / 2, self.nets[net])

    def masks(self, net, width):
        nid = self.nets[net]
        hw = width / 2
        narrow, wide = [], []
        for L in (0, 1):
            o = self.field.other(L, nid)
            narrow.append((o >= CLR + NARROW / 2 + EPS) & (self.edge >= EDGE + NARROW / 2))
            wide.append((o >= CLR + hw + EPS) & (self.edge >= EDGE + hw))
        r = VIA_D / 2
        via = ((self.field.other(0, nid) >= CLR + r + EPS) & (self.field.other(1, nid) >= CLR + r + EPS)
               & (self.edge >= EDGE + r) & ~self.field.pad[0] & ~self.field.pad[1])
        return [m.ravel() for m in narrow], [m.ravel() for m in wide], via.ravel()

    def pad_cells(self, pad, narrow):
        """Grid points inside a pad that a track may end on."""
        cells = []
        i0, i1 = int(math.ceil((pad["x"] - pad["hw"]) / G)), int(math.floor((pad["x"] + pad["hw"]) / G))
        j0, j1 = int(math.ceil((pad["y"] - pad["hh"]) / G)), int(math.floor((pad["y"] + pad["hh"]) / G))
        for j in range(j0, j1 + 1):
            for i in range(i0, i1 + 1):
                if pad["circle"] and math.hypot(i * G - pad["x"], j * G - pad["y"]) > pad["hw"]:
                    continue
                for L in pad["layers"]:
                    if narrow[L][j * NX + i]:
                        cells.append((L, i, j))
        return cells

    # --- the search

    def astar(self, sources, targets, goal, narrow, wide, via, power, crowd, crowd_via):
        """Cheapest path from any source cell to any target cell; None if there's none.

        Each cell is settled once, arriving from one direction (turn costs are charged from that), and the
        distance estimate is weighted, which trades a little optimality for a lot of speed. `crowd` is the
        extra cost of each point (other nets' tracks), `crowd_via` of a via there."""
        tset = set(targets)
        gx, gy = goal
        heap, best, parent, arrive, closed = [], {}, {}, {}, set()
        for c in sources:
            best[c] = 0.0
            parent[c] = None
            arrive[c] = 8
            heapq.heappush(heap, (HWEIGHT * math.hypot(c[1] - gx, c[2] - gy), 0.0, c))
        while heap:
            f, g, c = heapq.heappop(heap)
            if c in closed:
                continue
            closed.add(c)
            if c in tset:
                path = []
                while c is not None:
                    path.append(c)
                    c = parent[c]
                return path[::-1]
            if len(closed) > 2_500_000:
                return None
            L, i, j = c
            d = arrive[c]
            lc = BACK_COST if L else 1.0
            nm, wm, cr = narrow[L], wide[L], crowd[L]
            here = j * NX + i
            here_wide = wm[here]
            for nd in range(8):
                if d != 8:
                    turn = (nd - d) % 8
                    turn = min(turn, 8 - turn)
                    if turn > 2:
                        continue
                    tc = TURN_COST[turn]
                else:
                    tc = 0.0
                dx, dy = DIRS[nd]
                ni, nj = i + dx, j + dy
                if not (0 <= ni < NX and 0 <= nj < NY):
                    continue
                k = nj * NX + ni
                if not nm[k]:
                    continue
                n = (L, ni, nj)
                if n in closed:
                    continue
                step = (DIAG if dx and dy else 1.0) * lc
                if power and not (wm[k] and here_wide):
                    step *= NARROW_COST
                ng = g + step + tc + cr[k]
                if ng < best.get(n, math.inf):
                    best[n] = ng
                    parent[n] = c
                    arrive[n] = nd
                    heapq.heappush(heap, (ng + HWEIGHT * math.hypot(ni - gx, nj - gy), ng, n))
            if via[here]:
                n = (1 - L, i, j)
                ng = g + VIA_COST + crowd_via[here]
                if n not in closed and narrow[1 - L][here] and ng < best.get(n, math.inf):
                    best[n] = ng
                    parent[n] = c
                    arrive[n] = 8
                    heapq.heappush(heap, (ng + HWEIGHT * math.hypot(i - gx, j - gy), ng, n))
        return None

    # --- one net

    def route_net(self, net, pres):
        """Routes a net with other nets' tracks as a cost; returns an error, or None."""
        name = net.split(":")[0]               # "GND:U1" is some of GND's pads
        pads = self.pads[name]
        if net in LOCAL:
            pads = [p for p in pads if (p["ref"], p["num"]) in LOCAL[net]]
        width = POWER.get(name, NARROW)
        power = width > NARROW
        if name not in self.static:
            self.static[name] = self.masks(name, width)
        narrow, wide, via = self.static[name]
        o = self.occ
        crowd = [(pres * o.track[L] * (1 + o.hist[L]) + o.hist[L]).ravel().astype(np.float32).tolist()
                 for L in (0, 1)]
        crowd_via = (pres * (o.via[0] + o.via[1]) * (1 + o.hist[0] + o.hist[1])).ravel().astype(np.float32)
        crowd_via = crowd_via.tolist()
        nb = [m.tobytes() for m in narrow]
        wb = [m.tobytes() for m in wide]
        vb = via.tobytes()
        done = [pads[0]]
        tree = set(self.pad_cells(pads[0], nb))
        if not tree:
            return f"{pads[0]['ref']}.{pads[0]['num']} has no room for a track"
        todo = pads[1:]
        paths = []
        while todo:
            p = min(todo, key=lambda q: min(math.hypot(q["x"] - d["x"], q["y"] - d["y"]) for d in done))
            todo.remove(p)
            cells = self.pad_cells(p, nb)
            if not cells:
                return f"{p['ref']}.{p['num']} has no room for a track"
            if not tree & set(cells):
                path = self.astar(tree, cells, (p["x"] / G, p["y"] / G), nb, wb, vb, power, crowd, crowd_via)
                if path is None:
                    return f"no path to {p['ref']}.{p['num']}"
                paths.append(path)
                tree |= set(path)
            tree |= set(cells)
            done.append(p)
        objs = []
        for path in paths:
            objs += self.to_objects(path, wb, width)
        marks = [m for obj in objs for m in Occupancy.marks(obj)]
        cells = [c for path in paths for c in path]
        vias = [(o_[1], o_[2]) for o_ in objs if o_[0] == "v"]
        self.routes[net] = dict(objs=objs, marks=marks, cells=cells, vias=vias)
        self.occ.add(marks, +1)
        return None

    def rip_up(self, net):
        r = self.routes.pop(net, None)
        if r:
            self.occ.add(r["marks"], -1)

    def conflicts(self, net):
        """Points where this net's tracks or vias crowd another net's."""
        r = self.routes[net]
        self.occ.add(r["marks"], -1)
        bad = [c for c in r["cells"] if self.occ.track[c[0], c[2], c[1]] > 0]
        for x, y in r["vias"]:
            i, j = int(round(x / G)), int(round(y / G))
            if self.occ.via[0, j, i] > 0 or self.occ.via[1, j, i] > 0:
                bad += [(0, i, j), (1, i, j)]
        self.occ.add(r["marks"], +1)
        return bad

    @staticmethod
    def to_objects(path, wide, width):
        """A path of grid points as tracks ("t", layer, x1, y1, x2, y2, width) and vias ("v", x, y)."""
        def w_of(a, b):
            if width <= NARROW:
                return NARROW
            return width if wide[a[0]][a[2] * NX + a[1]] and wide[b[0]][b[2] * NX + b[1]] else NARROW

        objs = []
        run = [path[0]]
        runs = []
        for a, b in zip(path, path[1:]):
            if a[0] != b[0]:
                runs.append(run)
                objs.append(("v", a[1] * G, a[2] * G))
                run = [b]
                continue
            if len(run) >= 2:
                p0, p1 = run[-2], run[-1]
                if (p1[1] - p0[1], p1[2] - p0[2]) != (b[1] - a[1], b[2] - a[2]) or w_of(p0, p1) != w_of(a, b):
                    runs.append(run)
                    run = [a]
            run.append(b)
        runs.append(run)
        for run in runs:
            if len(run) >= 2:
                a, b = run[0], run[-1]
                objs.append(("t", a[0], a[1] * G, a[2] * G, b[1] * G, b[2] * G, w_of(run[0], run[1])))
        return objs

    # --- negotiation

    def negotiate(self):
        pres = PRES0
        todo = list(NETS)
        history = []
        for n in range(PASSES):
            t0 = time.time()
            for net in todo:
                self.rip_up(net)
                err = self.route_net(net, pres)
                if err:
                    raise SystemExit(f"{net}: {err}")
            bad = {net: self.conflicts(net) for net in NETS}
            bad = {k: v for k, v in bad.items() if v}
            for cells in bad.values():
                for L, i, j in cells:
                    self.occ.hist[L, j, i] += HIST
            print(f"pass {n + 1}: routed {len(todo)}, {len(bad)} nets still crowd another "
                  f"({time.time() - t0:.0f} s)" + (f": {sorted(bad)}" if len(bad) <= 4 else ""), flush=True)
            if not bad:
                return
            history.append(sorted(bad))
            if len(history) >= STUCK and all(h == history[-1] for h in history[-STUCK:]):
                break                      # the same few nets, pass after pass: see below
            todo = sorted(bad)
            pres *= PRES_GROW
        # What's left is usually legal: the crowding rule assumes the widest track. KiCad's DRC has the last word.
        for net, cells in bad.items():
            L, i, j = cells[len(cells) // 2]
            print(f"  {net} still crowds another net near ({i * G:.1f}, {j * G:.1f}) on "
                  f"{'B' if L else 'F'}.Cu")

    def finish(self):
        """Puts the final tracks into the exact field, for ground and checking."""
        self.tracks, self.vias = [], [("GND", x, y) for x, y in GND_VIAS]   # already in the field
        for net, r in self.routes.items():
            name = net.split(":")[0]
            nid = self.nets[name]
            for obj in r["objs"]:
                if obj[0] == "t":
                    self.add_track(nid, name, *obj[1:])
                else:
                    self.add_via(nid, obj[1], obj[2], name)

    def add_track(self, nid, net, L, x1, y1, x2, y2, w):
        self.tracks.append((net, L, x1, y1, x2, y2, w))
        self.field.segment(L, x1, y1, x2, y2, w / 2, nid)

    def via_room(self, x, y):
        """Whether a via here keeps clear of every other hole: vias of any net (the field only knows other
        nets') and plated pad holes."""
        return (all(math.hypot(x - vx, y - vy) >= VIA_SPACING for _, vx, vy in self.vias)
                and all(math.hypot(x - hx, y - hy) >= r + VIA_DRILL / 2 + 0.3 for hx, hy, r in self.holes))

    def add_via(self, nid, x, y, net):
        self.vias.append((net, x, y))
        self.field.circle([0, 1], x, y, VIA_D / 2, nid)

    # --- ground

    def ground(self):
        """A short track and a via from every surface-mount ground pad to the back layer's plane."""
        net = "GND"
        nid = self.nets[net]
        width = POWER[net]
        placed = 0
        zero = [0.0] * (NX * NY)
        for p in self.pads[net]:
            if not p["smd"] or (p["ref"] == "U2" and p["num"] == "11"):
                continue                            # U2's exposed pad has its own thermal vias
            narrow, wide, via = self.masks(net, width)
            nb = [narrow[0].tobytes(), bytes(NX * NY)]
            wb = [m.tobytes() for m in wide]
            cells = self.pad_cells(p, nb)
            if not cells:
                print(f"  {p['ref']}.{p['num']}: no room for a ground track")
                continue
            cx, cy = p["x"] / G, p["y"] / G
            targets = []
            for j in range(max(0, int(cy - 50)), min(NY, int(cy + 51))):
                for i in range(max(0, int(cx - 50)), min(NX, int(cx + 51))):
                    k = j * NX + i
                    if via[k] and nb[0][k] and self.via_room(i * G, j * G):
                        targets.append((0, i, j))
            # or an existing ground via
            for _, vx, vy in [v for v in self.vias if v[0] == net]:
                if math.hypot(vx - p["x"], vy - p["y"]) < 5.0:
                    targets.append((0, int(round(vx / G)), int(round(vy / G))))
            if not targets:
                print(f"  {p['ref']}.{p['num']}: no room for a ground via")
                continue
            near = min(targets, key=lambda t: math.hypot(t[1] - cx, t[2] - cy))
            path = self.astar(set(cells), targets, (near[1], near[2]), nb, wb, bytes(NX * NY), True,
                              [zero, zero], zero)
            if path is None:
                print(f"  {p['ref']}.{p['num']}: no path to a ground via")
                continue
            for obj in self.to_objects(path, wb, width):
                self.add_track(nid, net, *obj[1:])
            end = path[-1]
            if not any(abs(vx - end[1] * G) < 1e-6 and abs(vy - end[2] * G) < 1e-6 for _, vx, vy in self.vias):
                self.add_via(nid, end[1] * G, end[2] * G, net)
                placed += 1
        return placed

    def stitch(self, pitch=4.0):
        """Ground vias on a grid wherever there's room, to tie the two ground pours together."""
        nid = self.nets["GND"]
        need = CLR + VIA_D / 2 + 0.35          # room for the pour to reach the via, too
        ok = ((self.field.other(0, nid) >= need) & (self.field.other(1, nid) >= need)
              & (self.edge >= EDGE + 1.0) & ~self.field.pad[0] & ~self.field.pad[1])
        n = 0
        for y in np.arange(pitch / 2, H, pitch):
            for x in np.arange(pitch / 2, W, pitch):
                i, j = int(round(x / G)), int(round(y / G))
                if ok[j, i] and self.via_room(i * G, j * G):
                    self.add_via(nid, i * G, j * G, "GND")
                    n += 1
                    ok &= np.hypot(XS[None, :] - i * G, YS[:, None] - j * G) > 1.0
        return n

    # --- output

    def save(self):
        b = self.board
        self.to_board(self.tracks, self.vias)
        for prio, layer in enumerate((pcbnew.B_Cu, pcbnew.F_Cu)):
            z = pcbnew.ZONE(b)
            z.SetLayer(layer)
            z.SetNet(b.FindNet("GND"))
            z.SetAssignedPriority(prio)
            ol = z.Outline()
            ol.NewOutline()
            for x, y in [(0, 0), (W, 0), (W, H), (0, H)]:
                ol.Append(pcbnew.FromMM(OX + x), pcbnew.FromMM(OY + y))
            z.SetLocalClearance(pcbnew.FromMM(0.25))
            z.SetMinThickness(pcbnew.FromMM(0.25))
            z.SetThermalReliefGap(pcbnew.FromMM(0.3))
            z.SetThermalReliefSpokeWidth(pcbnew.FromMM(0.3))
            z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
            z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
            b.Add(z)
        pcbnew.ZONE_FILLER(b).Fill(b.Zones())
        self.drop_dangling()
        self.repair()
        b.Save(PCB)

    def to_board(self, tracks, vias):
        b = self.board
        for net, L, x1, y1, x2, y2, w in tracks:
            t = pcbnew.PCB_TRACK(b)
            t.SetStart(kpt(x1, y1))
            t.SetEnd(kpt(x2, y2))
            t.SetWidth(pcbnew.FromMM(w))
            t.SetLayer(pcbnew.B_Cu if L else pcbnew.F_Cu)
            t.SetNet(b.FindNet(net))
            b.Add(t)
        for net, x, y in vias:
            v = pcbnew.PCB_VIA(b)
            v.SetPosition(kpt(x, y))
            v.Padstack().SetSize(pcbnew.VECTOR2I(pcbnew.FromMM(VIA_D), pcbnew.FromMM(VIA_D)), pcbnew.F_Cu)
            v.SetDrill(pcbnew.FromMM(VIA_DRILL))
            v.SetViaType(pcbnew.VIATYPE_THROUGH)
            v.SetNet(b.FindNet(net))
            b.Add(v)

    def drop_dangling(self):
        """A stitching via whose pour was removed as an island on either layer joins nothing: drop it."""
        b = self.board
        tracked = {(t[2], t[3]) for t in self.tracks} | {(t[4], t[5]) for t in self.tracks}
        dropped = 0
        for v in [t for t in b.GetTracks() if isinstance(t, pcbnew.PCB_VIA)]:
            if v.GetNetname() != "GND":
                continue
            pos = v.GetPosition()
            on = [z.HitTestFilledArea(z.GetLayer(), pos) for z in b.Zones()]
            x, y = to_mm(pos)
            has_track = any(math.hypot(x - tx, y - ty) < 0.01 for tx, ty in tracked)
            if not all(on) and not (has_track and any(on)):
                b.Delete(v)
                dropped += 1
        if dropped:
            pcbnew.ZONE_FILLER(b).Fill(b.Zones())
        print(f"dropped {dropped} ground vias that the pour didn't reach")

    def islands(self):
        """The ground pour's pieces: (layer, polygons, index) for each filled island of each layer."""
        out = []
        for z in self.board.Zones():
            L = 1 if z.GetLayer() == pcbnew.B_Cu else 0
            polys = z.GetFilledPolysList(z.GetLayer())
            out += [(L, polys, i) for i in range(polys.OutlineCount())]
        return out

    def cut_off(self, islands):
        """Ground pads not joined to the main pour (the back layer's largest island), by our own walk over
        pads, tracks, vias and pour islands; and the islands that are joined to it."""
        tracks = [t for t in self.tracks if t[0] == "GND"]
        vias = [(x, y) for net, x, y in self.vias if net == "GND"]
        pads = self.pads["GND"]
        nodes = [("z", k) for k in range(len(islands))] + [("t", k) for k in range(len(tracks))] + \
                [("v", k) for k in range(len(vias))] + [("p", k) for k in range(len(pads))]
        parent = {n: n for n in nodes}

        def find(n):
            while parent[n] != n:
                parent[n] = parent[parent[n]]
                n = parent[n]
            return n

        def join(a, b):
            parent[find(a)] = find(b)

        def in_island(L, x, y):
            return [k for k, (IL, polys, i) in enumerate(islands) if IL == L and polys.Contains(kpt(x, y), i)]

        def pad_points(p):               # a 7 x 7 sample, so a thermal spoke into the pad is found
            return [(p["x"] + dx / 3 * p["hw"] * 0.98, p["y"] + dy / 3 * p["hh"] * 0.98)
                    for dx in range(-3, 4) for dy in range(-3, 4)]

        def in_pad(p, L, x, y):
            return L in p["layers"] and abs(x - p["x"]) <= p["hw"] + 1e-6 and abs(y - p["y"]) <= p["hh"] + 1e-6

        for k, (net, L, x1, y1, x2, y2, w) in enumerate(tracks):
            for x, y in ((x1, y1), (x2, y2)):
                for z in in_island(L, x, y):
                    join(("t", k), ("z", z))
                for v, (vx, vy) in enumerate(vias):
                    if math.hypot(vx - x, vy - y) < VIA_D / 2:
                        join(("t", k), ("v", v))
                for j, p in enumerate(pads):
                    if in_pad(p, L, x, y):
                        join(("t", k), ("p", j))
                for k2, t2 in enumerate(tracks[:k]):
                    if t2[1] == L and min(math.hypot(x - t2[2], y - t2[3]), math.hypot(x - t2[4], y - t2[5])) < 1e-6:
                        join(("t", k), ("t", k2))
        for v, (x, y) in enumerate(vias):
            for L in (0, 1):
                for z in in_island(L, x, y):
                    join(("v", v), ("z", z))
            for j, p in enumerate(pads):
                if any(in_pad(p, L, x, y) for L in (0, 1)):
                    join(("v", v), ("p", j))
        for j, p in enumerate(pads):
            for L in p["layers"]:
                for x, y in pad_points(p):
                    for z in in_island(L, x, y):
                        join(("p", j), ("z", z))
        back = [k for k, (L, polys, i) in enumerate(islands) if L == 1]
        main = find(("z", max(back, key=lambda k: abs(islands[k][1].Outline(islands[k][2]).Area()))))
        cut = [p for j, p in enumerate(pads) if find(("p", j)) != main]
        joined = [k for k in range(len(islands)) if find(("z", k)) == main]
        return cut, joined

    def repair(self):
        """Joins any ground pad cut off from the main pour (in a pocket walled in by tracks on both layers)
        to the nearest piece of pour that is joined to it, by the cheapest path through both layers."""
        b = self.board
        nid = self.nets["GND"]
        for attempt in range(4):
            islands = self.islands()
            cut, joined = self.cut_off(islands)
            if not cut:
                return
            narrow, wide, via = self.masks("GND", POWER["GND"])
            nb, wb, vb = [m.tobytes() for m in narrow], [m.tobytes() for m in wide], via.tobytes()
            zero = [0.0] * (NX * NY)
            pad = cut[0]
            cx, cy = pad["x"] / G, pad["y"] / G
            targets = []
            for j in range(max(0, int(cy - 80)), min(NY, int(cy + 81)), 2):
                for i in range(max(0, int(cx - 80)), min(NX, int(cx + 81)), 2):
                    for k in joined:
                        L, polys, idx = islands[k]
                        if nb[L][j * NX + i] and polys.Contains(kpt(i * G, j * G), idx):
                            targets.append((L, i, j))
                            break
            if not targets:
                print(f"  {pad['ref']}.{pad['num']}: cut off from the ground pour, which is nowhere near")
                return
            near = min(targets, key=lambda t: math.hypot(t[1] - cx, t[2] - cy))
            path = self.astar(set(self.pad_cells(pad, nb)), targets, (near[1], near[2]), nb, wb, vb, True,
                              [zero, zero], zero)
            if path is None:
                print(f"  {pad['ref']}.{pad['num']}: cut off from the ground pour, and no way to it")
                return
            n0, v0 = len(self.tracks), len(self.vias)
            for obj in self.to_objects(path, wb, POWER["GND"]):
                if obj[0] == "t":
                    self.add_track(nid, "GND", *obj[1:])
                else:
                    self.add_via(nid, obj[1], obj[2], "GND")
            self.to_board(self.tracks[n0:], self.vias[v0:])
            print(f"  joined {pad['ref']}.{pad['num']} to the ground pour "
                  f"({len(self.tracks) - n0} tracks, {len(self.vias) - v0} vias)")
            pcbnew.ZONE_FILLER(b).Fill(b.Zones())
        print("  some ground pads may still be cut off")


def main():
    t0 = time.time()
    bd = Board()
    bd.negotiate()
    bd.finish()
    print(f"ground vias at pads: {bd.ground()}, stitching vias: {bd.stitch()}")
    bd.save()
    print(f"{len(bd.tracks)} tracks, {len(bd.vias)} vias, "
          f"{sum(math.hypot(t[4] - t[2], t[5] - t[3]) for t in bd.tracks):.0f} mm of track "
          f"({time.time() - t0:.0f} s)")


if __name__ == "__main__":
    main()
