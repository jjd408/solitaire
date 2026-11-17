"""Finds a winning game, as button presses, for the full-game test (STEP6-moves.md, Checking it).

    python3 solve.py SEED [DRAW]            presses that win the game dealt from SEED, or exits 1
    python3 solve.py --find FROM [DRAW]     the first seed from FROM up that it can win, and its presses

A depth-first search over Klondike positions (draw 1 by default; unlimited passes), trying the moves most likely
to help first (cards to the foundations, moves that turn a card over), never visiting a position twice, and giving
up after a node limit. The moves are then turned into presses and played on klondike.py's model of the firmware,
which must end with the game won: so the presses are right for the firmware's own two-press rules (which run moves,
which foundation a card goes to). Prints the presses, starting with NEW, ten to a line.
"""
import sys

from deal import reference
from klondike import FACE_UP, P_FOUND1, P_STOCK, P_TAB1, P_WASTE, Machine

LIMIT = 300_000
RED = 0x20


def rank(c):
    return c & 15


def suit(c):
    return (c >> 4) & 3


def solve(seed, draw=1):
    piles = reference(seed)
    tab = [list(piles[P_TAB1 + i]) for i in range(7)]
    stock = list(piles[P_STOCK])
    waste = []
    found = [0, 0, 0, 0]                                # top rank by suit
    seen = set()
    path = []
    nodes = [0]

    def key():
        return (tuple(tuple(c) for c in tab), tuple(found), tuple(stock), tuple(waste))

    def fits_tab(c, col):
        if not col:
            return rank(c) == 13
        t = col[-1]
        return bool(t & FACE_UP) and bool((t ^ c) & RED) and rank(t) == rank(c) + 1

    def moves():
        out = []
        # to a foundation: from the waste or a column; safe ones (no card could need it) first
        red_min = min(found[2], found[3])
        black_min = min(found[0], found[1])
        for src in range(-1, 7):
            col = waste if src < 0 else tab[src]
            if col and found[suit(col[-1])] == rank(col[-1]) - 1:
                c = col[-1]
                other = black_min if c & RED else red_min
                safe = rank(c) <= 2 or rank(c) <= other + 1
                out.append((0 if safe else 3, ("F", src)))
        # column to column: the run that fits
        for s in range(7):
            col = tab[s]
            for i in range(len(col) - 1, -1, -1):
                if not col[i] & FACE_UP:
                    break
                for d in range(7):
                    if d != s and fits_tab(col[i], tab[d]):
                        reveals = i > 0 and not col[i - 1] & FACE_UP
                        if not tab[d] and i == 0:
                            continue                    # a king from the bottom of one column to another: pointless
                        out.append((1 if reveals else 5, ("T", s, d, len(col) - i)))
        # the waste to a column
        if waste:
            for d in range(7):
                if fits_tab(waste[-1], tab[d]):
                    out.append((2, ("W", d)))
        # the stock
        if stock or waste:
            out.append((4, ("S",)))
        # a foundation card back to a column
        for s in range(4):
            if found[s] > 2:
                c = (s << 4) | found[s] | FACE_UP
                for d in range(7):
                    if tab[d] and fits_tab(c, tab[d]):
                        out.append((6, ("U", s, d)))
        out.sort(key=lambda m: m[0])
        return [m for _, m in out]

    def apply(m):
        undo = None
        if m[0] == "F":
            col = waste if m[1] < 0 else tab[m[1]]
            c = col.pop()
            found[suit(c)] += 1
            turned = m[1] >= 0 and col and not col[-1] & FACE_UP
            if turned:
                col[-1] |= FACE_UP
            undo = ("F", m[1], c, turned)
        elif m[0] == "T":
            _, s, d, n = m
            run = tab[s][-n:]
            del tab[s][-n:]
            tab[d] += run
            turned = tab[s] and not tab[s][-1] & FACE_UP
            if turned:
                tab[s][-1] |= FACE_UP
            undo = ("T", s, d, n, turned)
        elif m[0] == "W":
            tab[m[1]].append(waste.pop())
            undo = ("W", m[1])
        elif m[0] == "S":
            if stock:
                n = min(draw, len(stock))
                for _ in range(n):
                    waste.append(stock.pop() | FACE_UP)
                undo = ("S", n)
            else:
                n = len(waste)
                while waste:
                    stock.append(waste.pop() & ~FACE_UP)
                undo = ("R", n)
        elif m[0] == "U":
            _, s, d = m
            tab[d].append((s << 4) | found[s] | FACE_UP)
            found[s] -= 1
            undo = ("U", s, d)
        return undo

    def unapply(u):
        if u[0] == "F":
            _, src, c, turned = u
            col = waste if src < 0 else tab[src]
            if turned:
                col[-1] &= ~FACE_UP
            col.append(c)
            found[suit(c)] -= 1
        elif u[0] == "T":
            _, s, d, n, turned = u
            if turned:
                tab[s][-1] &= ~FACE_UP
            run = tab[d][-n:]
            del tab[d][-n:]
            tab[s] += run
        elif u[0] == "W":
            waste.append(tab[u[1]].pop())
        elif u[0] == "S":
            for _ in range(u[1]):
                stock.append(waste.pop() & ~FACE_UP)
        elif u[0] == "R":
            for _ in range(u[1]):
                waste.append(stock.pop() | FACE_UP)
        elif u[0] == "U":
            _, s, d = u
            tab[d].pop()
            found[s] += 1

    def dfs():
        if found == [13, 13, 13, 13]:
            return True
        k = key()
        if k in seen:
            return False
        seen.add(k)
        nodes[0] += 1
        if nodes[0] > LIMIT:
            return False
        for m in moves():
            u = apply(m)
            path.append(m)
            if dfs():
                return True
            path.pop()
            unapply(u)
            if nodes[0] > LIMIT:
                return False
        return False

    sys.setrecursionlimit(100_000)
    return list(path) if dfs() else None


def presses(seed, draw, path):
    """The solver's moves as button presses, worked out on the firmware's model; checks they win."""
    m = Machine(seed, draw)
    names = ["NEW"]
    m.press("NEW")
    col = lambda i: f"T{i + 1}"

    def press(*ns):
        for n in ns:
            names.append(n)
            m.press(n)

    for mv in path:
        if mv[0] == "F":
            src = "WASTE" if mv[1] < 0 else col(mv[1])
            press(src, src)                             # the same button twice: to its foundation
        elif mv[0] == "T":
            press(col(mv[1]), col(mv[2]))
        elif mv[0] == "W":
            press("WASTE", col(mv[1]))
        elif mv[0] == "S":
            press("STOCK")
        elif mv[0] == "U":
            f = next(i for i in range(4) if m.piles[P_FOUND1 + i] and (m.piles[P_FOUND1 + i][-1] >> 4) & 3 == mv[1])
            press(f"F{f + 1}", col(mv[2]))
    return names, m


def main():
    args = sys.argv[1:]
    find = args and args[0] == "--find"
    if find:
        args = args[1:]
    if not args:
        print(__doc__)
        return 2
    seed = int(args[0], 0)
    draw = int(args[1]) if len(args) > 1 else 1
    while True:
        path = solve(seed, draw)
        if path:
            names, m = presses(seed, draw, path)
            if not m.won:
                print(f"seed 0x{seed:04X}: the solver's moves don't win on the model", file=sys.stderr)
                return 1
            print(f"# seed 0x{seed:04X}, draw {draw}: {len(path)} moves, {len(names)} presses, {m.moves} moves counted")
            for i in range(0, len(names), 10):
                print(" ".join(names[i:i + 10]))
            return 0
        if not find:
            print(f"seed 0x{seed:04X}: no win found", file=sys.stderr)
            return 1
        seed += 1


if __name__ == "__main__":
    sys.exit(main())
