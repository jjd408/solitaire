"""Writes the scripted press sequences the tests play (run.sh, steps 6 and 8), from klondike.py's model, so the
scripts exercise real play: mostly legal moves of every kind, with illegal tries, the stock, undo and options mixed
in. The choices come from a fixed random seed, so the files only change if this script does.

    python3 sequences.py            writes moves.txt, undo.txt, standard.txt, vegas.txt, passes.txt here

Each file starts with a comment saying what it covers.
"""
import copy
import os
import random

from klondike import P_FOUND1, P_TAB1, P_WASTE, ROLE_PILE, Machine

HERE = os.path.dirname(os.path.abspath(__file__))
PILE_NAME = {p: n for n, p in ROLE_PILE.items()}
SEED = 0x1234


def legal(m):
    """The moves the model would make, as (source, destination) button pairs, and to-foundation doubles."""
    out = []
    for s, sn in PILE_NAME.items():
        if not m.piles[s]:
            continue
        for d, dn in PILE_NAME.items():
            if d == s or d == P_WASTE:
                continue
            t = copy.deepcopy(m)
            if t.move(s, d):
                out.append((sn, dn))
        t = copy.deepcopy(m)
        if (s == P_WASTE or s >= P_TAB1) and t.to_foundation(s):
            out.append((sn, sn))
    return out


def play(rnd, steps, start, weights):
    """Presses from a fresh chip: start (a list of presses), then steps choices by weights."""
    m = Machine(SEED, 3)
    names = []

    def press(*ns):
        for n in ns:
            names.append(n)
            m.press(n)

    press(*start)
    for _ in range(steps):
        if m.won:
            break
        kinds, w = zip(*weights.items())
        kind = rnd.choices(kinds, w)[0]
        if kind == "move":
            moves = legal(m)
            if moves:
                press(*rnd.choice(moves))
                continue
            kind = "stock"
        if kind == "stock":
            press("STOCK")
        elif kind == "undo":
            press("UNDO")
        elif kind == "illegal":
            a, b = rnd.sample(list(PILE_NAME.values()), 2)
            press(a, b)
            if m.sel:
                press(PILE_NAME[m.sel], PILE_NAME[m.sel])       # (drop the selection again)
        elif kind == "select":
            a = rnd.choice(list(PILE_NAME.values()))
            press(a, a)                                         # select, then same again
    return names, m


def write(name, comment, names, m):
    with open(os.path.join(HERE, name), "w") as f:
        f.write(f"# {comment}\n# {len(names)} presses; at the end: {m.moves} moves, score {m.score}, "
                f"{sum(len(m.piles[P_FOUND1 + i]) for i in range(4))} cards on the foundations, undo log "
                f"{m.undo_count}, {'won' if m.won else 'not won'}. Made by sequences.py.\n")
        for i in range(0, len(names), 12):
            f.write(" ".join(names[i:i + 12]) + "\n")


def main():
    rnd = random.Random(6)
    names, m = play(rnd, 160, ["NEW"], {"move": 70, "stock": 15, "illegal": 10, "select": 5})
    write("moves.txt", "Step 6: play from seed 0x1234, draw 3: legal moves of every kind (runs between columns, "
          "kings to empty columns, foundation cards back down), the stock, illegal tries, same-button doubles",
          names, m)

    rnd = random.Random(8)
    names, m = play(rnd, 120, ["NEW"], {"move": 60, "stock": 15, "undo": 25})
    names += ["UNDO"] * (m.undo_count + 2)                      # then undo everything, and two more (nothing left)
    for n in ["UNDO"] * (m.undo_count + 2):
        m.press(n)
    write("undo.txt", "Step 8: play with undos mixed in, then undo back to the deal and try two more", names, m)

    rnd = random.Random(10)
    names, m = play(rnd, 120, ["OPTIONS", "F3", "OPTIONS", "NEW"], {"move": 70, "stock": 15, "undo": 15})
    write("standard.txt", "Step 8: standard scoring (set in the options before the deal), with undos", names, m)

    rnd = random.Random(12)
    names, m = play(rnd, 120, ["OPTIONS", "F3", "F3", "OPTIONS", "NEW"], {"move": 70, "stock": 15, "undo": 15})
    write("vegas.txt", "Step 8: Vegas scoring, with undos", names, m)

    names = ["OPTIONS", "F2", "F2", "F1", "OPTIONS", "NEW"] + ["STOCK"] * 52 + ["UNDO", "STOCK", "STOCK"]
    m = Machine(SEED, 3)
    for n in names:
        m.press(n)
    write("passes.txt", "Step 8: one pass through the stock in draw 1 (options S2 twice, S1): the stock runs out "
          "and won't turn over; undo and try again", names, m)


if __name__ == "__main__":
    main()
