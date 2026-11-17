"""Checks the stock button's work, read from the simulator, against a reference worked out here.

    msp430_run ... --peek ADDR:134 | python3 stock.py ADDR SEED PRESSES

ADDR is game_magic's address (the start of store.S's .persistent block; 134 words cover it), SEED the deal's seed,
PRESSES how many times STOCK was pressed after the deal. The reference deals as deal.py does, then plays the
presses with draw 3: each deals up to 3 cards from the stock to the waste, face up, the last dealt on top; with
the stock empty, the waste goes back to the stock face down, in its original order. Checks the stock and waste,
that the other piles are as dealt, and the counts after the piles: moves, draw, passes, won and last_move. Exits 0
if it all matches, else prints what differs and exits 1.
"""
import re
import sys

from deal import SIZES, card, reference

M_RECYCLED = 2


def main():
    addr, seed, presses = int(sys.argv[1], 16), int(sys.argv[2], 0), int(sys.argv[3])
    mem = {}
    for line in sys.stdin:
        m = re.match(r"^([0-9A-Fa-f]{4}): ((?:[0-9A-Fa-f]{4} ?)+)$", line.strip())
        if m:
            a = int(m.group(1), 16)
            for w in m.group(2).split():
                v = int(w, 16)
                mem[a], mem[a + 1] = v & 0xFF, v >> 8
                a += 2
    if addr not in mem or addr + 266 not in mem:
        print("no memory dump of the game: was the run given --peek ADDR:134?")
        return 1
    b = [mem[addr + i] for i in range(267)]
    piles, o = [], 12
    for size in SIZES:
        piles.append(list(b[o + 1:o + 1 + min(b[o], size - 1)]))
        o += size

    dealt = reference(seed)
    stock, waste = list(dealt[0]), []
    moves = passes = 0
    last = [0, 0, 0, 0]
    for _ in range(presses):
        if stock:
            n = min(3, len(stock))
            for _ in range(n):
                waste.append(stock.pop() | 0x80)
            last = [0, 1, n, 0]
        elif waste:
            n = len(waste)
            for _ in range(n):
                stock.append(waste.pop() & 0x7F)
            last = [1, 0, n, M_RECYCLED]
            passes += 1
        else:
            continue
        moves += 1

    problems = []
    for name, got, want in [("stock", piles[0], stock), ("waste", piles[1], waste)]:
        if got != want:
            problems.append(f"{name}: {' '.join(map(card, got))}; should be {' '.join(map(card, want))}")
    for i in range(2, 13):
        if piles[i] != dealt[i]:
            problems.append(f"pile {i} changed: the stock button should only touch the stock and waste")
    got = {"moves": b[258] | b[259] << 8, "draw": b[260], "passes": b[261], "won": b[262], "last_move": b[263:267]}
    want = {"moves": moves, "draw": 3, "passes": passes, "won": 0, "last_move": last}
    for k in want:
        if got[k] != want[k]:
            problems.append(f"{k} is {got[k]}, should be {want[k]}")
    if problems:
        print("\n".join(problems))
        return 1
    print(f"{presses} presses: stock {len(stock)}, waste {len(waste)}, moves {moves}, passes {passes}: as the reference")
    return 0


if __name__ == "__main__":
    sys.exit(main())
