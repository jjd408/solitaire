"""Checks a dealt game, read from the simulator, against a reference deal worked out here.

    msp430_run ... --peek ADDR:129 | python3 deal.py ADDR SEED DEALS

ADDR is game_magic's address (the start of store.S's .persistent block; 129 words cover it), SEED the deal's
seed, DEALS how many games should have been dealt. The reference repeats game.S in Python: xorshift32, rng_below,
make_deck, the Fisher-Yates shuffle and the deal. Exits 0 if the game in FRAM is exactly the reference deal,
else prints what differs and exits 1.

The block's layout, as in store.S: game_magic (2 bytes), seed (4), rng (4), deals (2), then the piles, each a
count byte and room for its cards: stock 25, waste 25, foundations 4 x 14, tableau 7 x 20.
"""
import re
import sys

GAME_MAGIC = 0x50CA
SIZES = [25, 25] + [14] * 4 + [20] * 7
NAMES = ["stock", "waste"] + [f"foundation {n}" for n in range(1, 5)] + [f"column {n}" for n in range(1, 8)]


def xorshift(x):
    x ^= (x << 13) & 0xFFFFFFFF
    x ^= x >> 17
    x ^= (x << 5) & 0xFFFFFFFF
    return x


def reference(seed):
    """The 13 piles, bottom card first, as game_new deals them."""
    x = seed or 1
    deck = [(k // 13) << 4 | (k % 13 + 1) for k in range(52)]
    for i in range(51, 0, -1):
        x = xorshift(x)
        j = ((x >> 16) * (i + 1)) >> 16
        deck[i], deck[j] = deck[j], deck[i]
    piles = [[] for _ in range(13)]
    k = 0
    for row in range(7):
        for col in range(row, 7):
            piles[6 + col].append(deck[k] | (0x80 if col == row else 0))
            k += 1
    piles[0] = deck[k:]
    return piles


def card(c):
    if not c:
        return "none"
    s = "A23456789TJQK"[(c & 15) - 1] + "SCHD"[(c >> 4) & 3]
    return s if c & 0x80 else f"({s})"


def main():
    addr, seed, deals = int(sys.argv[1], 16), int(sys.argv[2], 0), int(sys.argv[3])
    mem = {}
    for line in sys.stdin:
        m = re.match(r"^([0-9A-Fa-f]{4}): ((?:[0-9A-Fa-f]{4} ?)+)$", line.strip())
        if m:
            a = int(m.group(1), 16)
            for w in m.group(2).split():
                v = int(w, 16)
                mem[a], mem[a + 1] = v & 0xFF, v >> 8
                a += 2
    if addr not in mem or addr + 257 not in mem:
        print("no memory dump of the game: was the run given --peek ADDR:129?")
        return 1
    b = [mem[addr + i] for i in range(258)]
    word = lambda o: b[o] | b[o + 1] << 8
    problems = []
    if word(0) != GAME_MAGIC:
        problems.append(f"game_magic is 0x{word(0):04X}, not 0x{GAME_MAGIC:04X}: no game")
    got_seed = word(2) | word(4) << 16
    if got_seed != seed:
        problems.append(f"the seed kept is 0x{got_seed:08X}, not 0x{seed:08X}")
    if word(10) != deals:
        problems.append(f"deals is {word(10)}, not {deals}")
    piles, o = [], 12
    for size in SIZES:
        n = b[o]
        piles.append(b[o + 1:o + 1 + min(n, size - 1)])
        o += size
    want = reference(seed)
    for name, got, ref in zip(NAMES, piles, want):
        if got != ref:
            diff = next((i for i in range(max(len(got), len(ref)))
                         if i >= len(got) or i >= len(ref) or got[i] != ref[i]), 0)
            problems.append(f"{name}: {len(got)} cards, should be {len(ref)}; card {diff + 1} from the bottom is "
                            f"{card(got[diff]) if diff < len(got) else 'missing'}, should be "
                            f"{card(ref[diff]) if diff < len(ref) else 'none'}")
    everything = sorted(c & 0x3F for p in piles for c in p)
    if everything != sorted((k // 13) << 4 | (k % 13 + 1) for k in range(52)):
        problems.append("the piles don't hold each of the 52 cards exactly once")
    if problems:
        print("\n".join(problems))
        return 1
    print(f"seed 0x{seed:08X}: all 13 piles as the reference deal; 52 cards, each once")
    return 0


if __name__ == "__main__":
    sys.exit(main())
