"""A model of the solitaire firmware, for checking it: the game (game.S), what's kept in FRAM (store.S), and what
each button does (ui.S, options.S), worked out independently in Python.

    python3 klondike.py check ADDR SEED DRAW ROLES < report      compare FRAM after the presses with the model
    python3 klondike.py pins ROLES START [PERIOD]                runner options pressing those buttons

ROLES is a file (NAME.txt) of button names, separated by spaces or new lines (T1-T7, WASTE, STOCK, F1-F4, NEW,
UNDO, OPTIONS; # starts a comment), or the names themselves in one argument ("NEW T1 T2"). RESET restarts the chip;
RESET_CORRUPT_MOVES and RESET_CORRUPT_CARDS restart a TEST_CORRUPT=1 or =2 build, which damages the game. check reads the runner's report (--peek ADDR:660) on stdin; ADDR is game_magic's
address, SEED the build's TEST_SEED, DRAW its TEST_DRAW (the draw option it starts with). It plays the presses on
the model from a fresh chip (no game, default settings) and compares every byte of the saved game, settings and
statistics, and that the game is sealed (its checksum). Exits 0 if they all match.
"""
import re
import sys

from deal import reference

# sol.h
P_STOCK, P_WASTE, P_FOUND1, P_TAB1, P_PILES = 0, 1, 2, 6, 13
FACE_UP, RANK, SUIT, RED = 0x80, 0x0F, 0x30, 0x20
M_TURNED, M_RECYCLED = 1, 2
S_OFF, S_STANDARD, S_VEGAS = 0, 1, 2
GAME_MAGIC, STORE_VERSION, SETTINGS_MAGIC, UNDO_SIZE = 0x50CA, 2, 0x5E77, 256
STOCK_NONE, STOCK_DONE, STOCK_LIMIT = 0, 1, 2
SIZES = [25, 25] + [14] * 4 + [20] * 7

ROLES = {"T1": 1, "T2": 2, "T3": 3, "T4": 4, "T5": 5, "T6": 6, "T7": 7, "WASTE": 8, "STOCK": 9,
         "F1": 10, "F2": 11, "F3": 12, "F4": 13, "NEW": 14, "UNDO": 15, "OPTIONS": 16}
# the package pin of each button (sw/sol/tests/run.sh, step 4)
PINS = {"T1": 7, "T2": 6, "T3": 5, "T4": 4, "T5": 31, "T6": 30, "T7": 29, "WASTE": 27, "STOCK": 26,
        "F1": 25, "F2": 24, "F3": 15, "F4": 14, "NEW": 3, "UNDO": 2, "OPTIONS": 1}
# not buttons: RST pulled low (package pin 9) and let go, restarting the chip; in a TEST_CORRUPT build the kept
# game is damaged as it starts (ui.S): 1 a count (the checksum fails, the cards are fine), 2 a card (doubled)
RESETS = {"RESET": None, "RESET_CORRUPT_MOVES": 1, "RESET_CORRUPT_CARDS": 2}
ROLE_PILE = {**{f"T{n}": P_TAB1 + n - 1 for n in range(1, 8)}, "WASTE": P_WASTE,
             **{f"F{n}": P_FOUND1 + n - 1 for n in range(1, 5)}}


def rank(c):
    return c & RANK


def is_found(p):
    return P_FOUND1 <= p < P_TAB1


def is_tab(p):
    return P_TAB1 <= p < P_TAB1 + 7


class Machine:
    """The chip's FRAM and the interface's RAM, from a freshly programmed chip."""

    def __init__(self, seed, draw_option=3):
        self.test_seed = seed
        # the game (store.S)
        self.magic = 0
        self.seed = 0
        self.deals = 0
        self.piles = [[] for _ in range(P_PILES)]
        self.moves = 0
        self.draw = 3
        self.passes = 0
        self.won = 0
        self.last = [0, 0, 0, 0]
        self.max_passes = 0
        self.scoring = 0
        self.score = 0
        self.undo_count = 0
        self.undo_next = 0
        self.log = bytearray(4 * UNDO_SIZE)
        self.version = 0
        # the settings and statistics
        self.opt_draw, self.opt_passes, self.opt_scoring = draw_option, 0, 0
        self.played = self.won_count = self.streak = self.best = self.wdt_resets = 0
        # the interface (RAM)
        self.sel = 0
        self.confirm = 0
        self.options = False
        self.arm = 0
        self.msg = None

    # ---- game.S ----
    def top(self, p):
        return self.piles[p][-1] if self.piles[p] else 0

    def fits(self, card, p):
        t = self.top(p)
        if is_found(p):
            if not t:
                return rank(card) == 1
            return not ((t ^ card) & SUIT) and rank(card) == rank(t) + 1
        if is_tab(p):
            if not t:
                return rank(card) == 13
            return bool(t & FACE_UP) and bool((t ^ card) & RED) and rank(t) == rank(card) + 1
        return False

    def score_delta(self):
        src, dst, _, flags = self.last
        onto, off = is_found(dst), is_found(src)
        tf = (1 if onto else 0) - (1 if off else 0)
        if self.scoring == S_VEGAS:
            return 5 * tf
        if self.scoring != S_STANDARD:
            return 0
        d = 5 if flags & M_TURNED else 0
        if flags & M_RECYCLED:
            return d - 100 if self.draw == 1 else d
        if tf == 1:
            return d + 10
        if tf == -1:
            return d - 15
        if src == P_WASTE and is_tab(dst):
            return d + 5
        return d

    def record(self, src, dst, n, flags):
        self.last = [src, dst, n, flags]
        o = 4 * self.undo_next
        self.log[o:o + 4] = bytes(self.last)
        self.undo_next = (self.undo_next + 1) & 0xFF
        self.undo_count = min(self.undo_count + 1, UNDO_SIZE)
        self.moves += 1
        self.score += self.score_delta()

    def move(self, src, dst):
        if src == dst or not (P_WASTE <= src < P_TAB1 + 7) or not (P_FOUND1 <= dst < P_TAB1 + 7):
            return False
        pile = self.piles[src]
        if not pile:
            return False
        if is_tab(dst) and is_tab(src):
            n = 0
            for i in range(len(pile) - 1, -1, -1):
                if not pile[i] & FACE_UP:
                    return False
                if self.fits(pile[i], dst):
                    n = len(pile) - i
                    break
            if not n:
                return False
        else:
            if not self.fits(pile[-1], dst):
                return False
            n = 1
        run = pile[-n:]
        del pile[-n:]
        self.piles[dst] += run
        flags = 0
        if is_tab(src) and pile and not pile[-1] & FACE_UP:
            pile[-1] |= FACE_UP
            flags = M_TURNED
        self.record(src, dst, n, flags)
        if all(len(self.piles[P_FOUND1 + f]) == 13 for f in range(4)):
            self.won = 1
            self.won_count += 1
            self.streak += 1
            self.best = max(self.best, self.streak)
        return True

    def to_foundation(self, src):
        if not (src == P_WASTE or is_tab(src)) or not self.piles[src]:
            return 0
        for f in range(P_FOUND1, P_FOUND1 + 4):
            if self.fits(self.piles[src][-1], f):
                return f if self.move(src, f) else 0
        return 0

    def deal_cards(self, src, dst, n, face):
        for _ in range(n):
            c = self.piles[src].pop()
            self.piles[dst].append((c & ~FACE_UP) | face)

    def stock(self):
        if self.piles[P_STOCK]:
            n = min(self.draw, len(self.piles[P_STOCK]))
            self.deal_cards(P_STOCK, P_WASTE, n, FACE_UP)
            self.record(P_STOCK, P_WASTE, n, 0)
            return STOCK_DONE
        n = len(self.piles[P_WASTE])
        if not n:
            return STOCK_NONE
        if self.max_passes and self.passes + 1 >= self.max_passes:
            return STOCK_LIMIT
        self.deal_cards(P_WASTE, P_STOCK, n, 0)
        self.passes += 1
        self.record(P_WASTE, P_STOCK, n, M_RECYCLED)
        return STOCK_DONE

    def undo(self):
        if not self.undo_count or self.won:
            return False
        self.undo_count -= 1
        self.undo_next = (self.undo_next - 1) & 0xFF
        o = 4 * self.undo_next
        self.last = list(self.log[o:o + 4])
        self.score -= self.score_delta()
        self.moves -= 1
        src, dst, n, flags = self.last
        if flags & M_RECYCLED:
            self.deal_cards(P_STOCK, P_WASTE, n, FACE_UP)
            self.passes -= 1
        elif src == P_STOCK:
            self.deal_cards(P_WASTE, P_STOCK, n, 0)
        else:
            if flags & M_TURNED:
                self.piles[src][-1] &= ~FACE_UP
            run = self.piles[dst][-n:]
            del self.piles[dst][-n:]
            self.piles[src] += run
        return True

    def new(self):
        if self.magic == GAME_MAGIC and not self.won:
            self.streak = 0
        self.played += 1
        self.seed = self.test_seed
        self.piles = [list(p) for p in reference(self.test_seed)]
        self.draw, self.max_passes, self.scoring = self.opt_draw, self.opt_passes, self.opt_scoring
        self.score = -52 if self.scoring == S_VEGAS else 0
        self.moves = self.passes = self.won = 0
        self.last = [0, 0, 0, 0]
        self.undo_count = self.undo_next = 0
        self.deals += 1
        self.version = STORE_VERSION
        self.magic = GAME_MAGIC
        self.sel = 0

    # ---- a restart (ui_start) ----
    def reset(self, corrupt):
        self.sel = self.confirm = self.arm = 0
        self.options = False
        self.msg = None
        if self.magic != GAME_MAGIC:
            return
        if corrupt == 1:
            self.moves += 1                 # the checksum fails, but the cards are all there: kept, without undo
            self.undo_count = 0
        elif corrupt == 2:
            self.magic = 0                  # a card doubled: the game is dropped

    # ---- ui.S and options.S ----
    def press(self, name):
        if name in RESETS:
            return self.reset(RESETS[name])
        role = ROLES[name]
        if self.options:
            return self.options_press(name)
        self.msg = None
        if name == "OPTIONS":
            self.sel = 0
            self.confirm = 0
            self.options = True
            self.arm = 0
            return
        if self.magic != GAME_MAGIC or self.won:
            if name == "NEW":
                self.confirm = 0
                self.new()
            return
        if name == "NEW":
            self.sel = 0
            if self.moves == 0 or self.confirm:
                self.confirm = 0
                self.new()
            else:
                self.confirm = 1
                self.msg = "confirm"
            return
        self.confirm = 0
        if name == "UNDO":
            self.sel = 0
            if not self.undo():
                self.msg = "undo"
            return
        if name == "STOCK":
            self.sel = 0
            if self.stock() == STOCK_LIMIT:
                self.msg = "passes"
            return
        p = ROLE_PILE.get(name)
        assert role and p is not None
        if not self.sel:
            if self.piles[p]:
                self.sel = p
            else:
                self.msg = "empty"
        elif self.sel == p:
            self.sel = 0
            self.to_foundation(p)
        elif self.move(self.sel, p):
            self.sel = 0
        else:
            self.msg = "cant"

    def options_press(self, name):
        if name == "OPTIONS":
            self.arm = 0
            self.options = False
        elif name == "F4":
            if self.arm:
                self.arm = 0
                self.played = self.won_count = self.streak = self.best = self.wdt_resets = 0
            else:
                self.arm = 1
        else:
            self.arm = 0
            if name == "F1":
                self.opt_draw ^= 1 ^ 3
            elif name == "F2":
                self.opt_passes = {0: 3, 3: 1, 1: 0}[self.opt_passes]
            elif name == "F3":
                self.opt_scoring = (self.opt_scoring + 1) % 3

    # ---- store.S: the bytes in FRAM ----
    def image(self):
        """The .persistent block, as store.S lays it out: 1320 bytes."""
        b = bytearray(1320)
        w = lambda o, v: b.__setitem__(slice(o, o + 2), (v & 0xFFFF).to_bytes(2, "little"))
        w(0, self.magic)
        w(2, self.seed & 0xFFFF)
        w(4, self.seed >> 16)
        w(10, self.deals)
        o = 12
        for size, pile in zip(SIZES, self.piles):
            b[o] = len(pile)
            b[o + 1:o + 1 + len(pile)] = bytes(pile)
            o += size
        w(258, self.moves)
        b[260], b[261], b[262] = self.draw, self.passes, self.won
        b[263:267] = bytes(self.last)
        b[267], b[268] = self.max_passes, self.scoring
        w(270, self.score)
        w(272, self.undo_count)
        b[274] = self.undo_next
        b[276:1300] = self.log
        w(1300, self.version)
        w(1302, checksum(b))
        w(1304, SETTINGS_MAGIC)
        b[1306], b[1307], b[1308] = self.opt_draw, self.opt_passes, self.opt_scoring
        for i, v in enumerate([self.played, self.won_count, self.streak, self.best, self.wdt_resets]):
            w(1310 + 2 * i, v)
        return b


def checksum(b):
    """store_sum: over the words from game_magic to game_version, sum = (sum rotated left one bit) + word."""
    s = 0
    for o in range(0, 1302, 2):
        s = ((s << 1) | (s >> 15)) & 0xFFFF
        s = (s + (b[o] | b[o + 1] << 8)) & 0xFFFF
    return s


# Which bytes of the image are what, for saying where they differ
FIELDS = [(0, 2, "game_magic"), (2, 6, "seed"), (6, 10, "rng"), (10, 12, "deals")]
_o = 12
for _name, _size in zip(["stock", "waste"] + [f"foundation {n}" for n in range(1, 5)] +
                        [f"column {n}" for n in range(1, 8)], SIZES):
    FIELDS.append((_o, _o + _size, _name))
    _o += _size
FIELDS += [(258, 260, "moves"), (260, 261, "draw"), (261, 262, "passes"), (262, 263, "won"), (263, 267, "last_move"),
           (267, 268, "max_passes"), (268, 269, "scoring"), (270, 272, "score"), (272, 274, "undo_count"),
           (274, 275, "undo_next"), (276, 1300, "undo_log"), (1300, 1302, "game_version"), (1302, 1304, "game_sum"),
           (1304, 1306, "settings_magic"), (1306, 1307, "opt_draw"), (1307, 1308, "opt_passes"),
           (1308, 1309, "opt_scoring"), (1310, 1312, "stat_played"), (1312, 1314, "stat_won"),
           (1314, 1316, "stat_streak"), (1316, 1318, "stat_best"), (1318, 1320, "wdt_resets")]


def card(c):
    s = "A23456789TJQK"[(c & 15) - 1] + "SCHD"[(c >> 4) & 3] if c & 15 else "??"
    return s if c & 0x80 else f"({s})"


def read_roles(path):
    """The presses in a file, or written out in the argument itself ("NEW T1 T2")."""
    lines = open(path) if " " not in path and path.endswith(".txt") else [path]
    names = []
    for line in lines:
        names += line.split("#")[0].split()
    for n in names:
        if n not in ROLES and n not in RESETS:
            raise SystemExit(f"unknown button {n} in {path}")
    return names


def read_memory(stream, addr, n):
    mem = {}
    for line in stream:
        m = re.match(r"^([0-9A-Fa-f]{4}): ((?:[0-9A-Fa-f]{4} ?)+)$", line.strip())
        if m:
            a = int(m.group(1), 16)
            for w in m.group(2).split():
                v = int(w, 16)
                mem[a], mem[a + 1] = v & 0xFF, v >> 8
                a += 2
    if any(addr + i not in mem for i in range(n)):
        return None
    return bytearray(mem[addr + i] for i in range(n))


def play(seed, draw, names):
    m = Machine(seed, draw)
    for n in names:
        m.press(n)
    return m


def check(addr, seed, draw, names, stream):
    got = read_memory(stream, addr, 1320)
    if got is None:
        print("no memory dump of FRAM: was the run given --peek ADDR:660?")
        return 1
    m = play(seed, draw, names)
    want = m.image()
    if m.magic != GAME_MAGIC:
        # no game: only the settings and statistics, and that game_magic isn't GAME_MAGIC
        want[0:1304] = got[0:1304]
        if got[0] | got[1] << 8 == GAME_MAGIC:
            print("game_magic says there's a game: there shouldn't be")
            return 1
    else:
        want[6:10] = got[6:10]      # the generator's state: deal.py checks the deal itself
        o = 12                      # a pile's bytes past its count are old cards, never cleared: not compared
        for size in SIZES:
            n = got[o] + 1
            if got[o] == want[o]:
                want[o + n:o + size] = got[o + n:o + size]
            o += size
        want[1302:1304] = got[1302:1304]    # the seal is checked against what was read, below
    problems = []
    for lo, hi, name in FIELDS:
        if got[lo:hi] != want[lo:hi]:
            if name in ("stock", "waste") or name.startswith(("foundation", "column")):
                problems.append(f"{name}: {' '.join(card(c) for c in got[lo + 1:lo + 1 + got[lo]])}; should be "
                                f"{' '.join(card(c) for c in want[lo + 1:lo + 1 + want[lo]])}")
            elif hi - lo == 2:
                problems.append(f"{name} is {got[lo] | got[lo + 1] << 8}, should be {want[lo] | want[lo + 1] << 8}")
            elif hi - lo <= 4:
                problems.append(f"{name} is {list(got[lo:hi])}, should be {list(want[lo:hi])}")
            else:
                i = next(i for i in range(lo, hi) if got[i] != want[i])
                problems.append(f"{name} differs from byte {i - lo}")
    if m.magic == GAME_MAGIC and (got[1302] | got[1303] << 8) != checksum(got):
        problems.append("the game isn't sealed: game_sum doesn't match it")
    if problems:
        print("\n".join(problems))
        return 1
    print(f"{len(names)} presses: FRAM as the model ({m.moves} moves, {'won' if m.won else 'not won'})")
    return 0


def pins(names, start, period):
    out = []
    t = start
    for n in names:
        if n in RESETS:
            out.append(f"--pin 9=0@{t:.3f} --pin 9=1@{t + 0.01:.3f}")     # RST: driven high again after
        else:
            out.append(f"--pin {PINS[n]}=0@{t:.3f} --pin {PINS[n]}=z@{t + 0.06:.3f}")
        t += period
    print(" ".join(out))


def main():
    if len(sys.argv) >= 6 and sys.argv[1] == "check":
        return check(int(sys.argv[2], 16), int(sys.argv[3], 0), int(sys.argv[4]), read_roles(sys.argv[5]), sys.stdin)
    if len(sys.argv) >= 4 and sys.argv[1] == "pins":
        pins(read_roles(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]) if len(sys.argv) > 4 else 0.2)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
