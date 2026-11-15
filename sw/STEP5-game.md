# Step 5: the game model

From the plan (`PLAN.md`, Milestones):

> **Game model**: cards, piles in `.persistent`, rng, shuffle, deal, the draw of the opening layout. Check:
> seeded deals match expected layouts.

The goal: the handheld deals a real Klondike game, shuffled from a random seed, keeps it in FRAM, and shows the
opening layout. No moves yet (step 6); the only button that does anything is NEW, which deals another game.

## 1. Cards and piles

**A card is one byte** (`sol.h` already has the names, from step 3):

| Bits | Meaning |
| --- | --- |
| 0–3 | Rank, 1 (ace) to 13 (king) |
| 4–5 | Suit: 0 spades, 1 clubs, 2 hearts, 3 diamonds (bit 5 set: red) |
| 6 | Unused in piles (`SELECTED` is only ever passed to `gfx_card`) |
| 7 | `FACE_UP` |

So a card's number 0–51, suit × 13 + rank − 1, isn't stored anywhere: the byte is the card.

**Thirteen piles**, each a count byte followed by room for its most cards. Moves only add to or take from the
end, so a pile is a simple stack: its top card is `pile[count]` (the cards are at offsets 1 to count).

| Pile | Number (`sol.h`) | Most cards | Bytes |
| --- | --- | --- | --- |
| Stock | `P_STOCK` 0 | 24 | 25 |
| Waste | `P_WASTE` 1 | 24 | 25 |
| Foundations 1–4 | `P_FOUND1`–`P_FOUND4` 2–5 | 13 | 14 each |
| Tableau 1–7 | `P_TAB1`–`P_TAB7` 6–12 | 19 (6 face down + 13 face up) | 20 each |

That's 246 bytes in all. A table in `.rodata`, `pile_addr`, gives each pile's address by number, so code can
work on "pile n" without knowing where it is; the pile numbers line up with the button roles where it helps
(`B_TABLEAU1` is 1, `P_TAB1` is 6: pile = role + 5 for the tableau).

**Small routines in `game.S`** for the piles, used by the deal now and by moves in step 6:

| Routine | In | Out | Does |
| --- | --- | --- | --- |
| `pile_count` | R12 pile | R12 count | |
| `pile_top` | R12 pile | R12 card, or 0 if empty | |
| `pile_card` | R12 pile, R13 index (1 = bottom) | R12 card | |
| `pile_push` | R12 pile, R13 card | | Adds a card on top (FRAM must be writable: section 2) |
| `pile_pop` | R12 pile | R12 card | Takes the top card off |

## 2. Where the game lives: `.persistent`, in FRAM

The game goes in FRAM, not RAM: there isn't room for it in RAM beside the framebuffer, and in FRAM it survives
a reset or the batteries coming out (the plan's "saving", finished in step 9, comes from this).

```asm
        .section .persistent, "aw"
        .balign 2
game_magic: .word 0                                     ; GAME_MAGIC once a game has been dealt
seed:       .word 0, 0                                  ; the deal's seed (32 bits)
rng:        .word 0, 0                                  ; the generator's state
deals:      .word 0                                     ; games dealt, ever: mixed into each seed
stock:      .skip 25
waste:      .skip 25
found1:     .skip 14
...
```

- **`.persistent` gets its starting values when the program is loaded** (TI's linker script puts it in FRAM,
  loaded but not cleared by the start-up code). So a freshly programmed chip has `game_magic` 0: no game yet.
  After that the start-up code leaves it alone, so a reset keeps the game.
- **Writing it needs FRAM write protection off.** `SYSCFG0.PFWP` protects program FRAM (where `.persistent`
  is, beside the code) from stray writes; the simulator enforces it like the chip. Two routines in `store.S`:
  ```asm
  store_open:                                             ; FRAM writable
          mov.w   #FRWPPW|DFWP, &SYSCFG0                  ; password; PFWP clear, info FRAM still protected
          ret
  store_close:                                            ; and protected again
          mov.w   #FRWPPW|DFWP|PFWP, &SYSCFG0
          ret
  ```
  Every change to the game is wrapped in `store_open` … `store_close`, so the code and constants are only
  writable for those few instructions. (Writes to `SYSCFG0` need the `FRWPPW` password in the high byte, like
  `WDTCTL`.) Step 9 adds a version and checksum (`store_valid`); for now `game_magic` is enough.
- **A new firmware version can move `.persistent`'s contents.** Loading a new build also loads its starting
  values, so it always starts without a game; that's fine during development.

## 3. Random numbers: xorshift32 (`rng.S`)

```
x ^= x << 13
x ^= x >> 17
x ^= x << 5
```
Marsaglia's xorshift32: a 32-bit state, any value but 0, three shifts and XORs a number, period 2^32 − 1. Small,
fast and plenty good for shuffling cards.

**In assembly**, the state is two words, R13:R12 (high:low), loaded from `rng` and stored back:
- `x << 13`: a copy shifted left 13 times as one 32-bit number: `rla.w` the low word, `rlc.w` the high word
  (the carry moves bit 15 of the low word into bit 0 of the high one), 13 times; then XOR both words into x.
- `x >> 17`: a 16-word move does most of it: the copy's low word = x's high word, its high word = 0; then one
  more right shift (`clrc`, `rrc.w`); XOR into x.
- `x << 5`: as `<< 13`, 5 times.

Speed doesn't matter here (a shuffle is 51 numbers), so plain loops are fine.

| Routine | In | Out |
| --- | --- | --- |
| `rng_seed` | R13:R12 seed (made non-zero if 0) | |
| `rng_next` | | R13:R12 the next value (also kept in `rng`) |
| `rng_below` | R12 n (1–65535) | R12 a random number 0 to n − 1 |

**`rng_below`** uses the hardware multiplier: the next value's high word × n, keeping the high word of the
32-bit product, is a number 0 to n − 1, evenly enough spread (the bias is at most n / 65536, under 0.1% for a
deck):
```asm
rng_below:
        push.w  R12                                     ; n, kept on the stack: rng_next changes R12-R15
        call    #rng_next
        mov.w   R13, &MPY                               ; the high word: xorshift's better bits
        pop.w   &OP2                                    ; × n (writing OP2 starts the multiply)
        mov.w   &RESHI, R12                             ; the result's high word: 0 to n - 1
        ret
```
(Checked on the simulator: from seed 0x1234, after four `rng_next`s, five `rng_below(7)`s give 3, 4, 0, 1, 4.)

**Reference values**, to check the code against: from seed 0x00001234 the first four values are
0x4A94F1F7, 0x41E50FE2, 0xE33EC22E, 0x5418EDF3.

## 4. Seeding

A different game every time needs an unpredictable seed, and the chip has no random source. People's timing is
one: the plan's seed is **TB0's count at the moment NEW is pressed** (512 Hz, so the press time to 2 ms),
mixed with **`deals`**, the count of games dealt, which goes up by one each time (so even two presses at the
same count give different games). The press time is in `TB0R`, read in the port interrupt; the event queue
carries only roles, so `p3_isr` saves the count in a variable (`press_time`) as it queues the event.

```
seed = (deals << 16 | press_time) ^ 0x9E3779B9           ; the constant spreads the bits; deals += 1
```

**A fixed seed for the tests**: built with `-DTEST_SEED=0x1234`, `game_new` ignores the press and always deals
from that seed, so the deal is the same every run, and checkable.

## 5. Shuffle and deal (`game_new`, in `game.S`)

1. **`store_open` first:** the generator's state (`rng`) is in `.persistent`, so seeding and every
   `rng_next` write FRAM. With PFWP set those writes are ignored, the state stays 0, and xorshift gives 0 for
   ever: every "shuffle" leaves the deck in order.
2. `rng_seed`; make the 52 cards in order in a RAM scratch deck (52 bytes): spades A–K, clubs, hearts, diamonds
   (card k = (k / 13) << 4 | (k % 13 + 1)).
3. **Fisher–Yates shuffle:** for i from 51 down to 1, j = `rng_below`(i + 1), swap deck[i] and deck[j]. Then
   empty all 13 piles.
4. **Deal**, as dealt by hand, a row at a time: for row 0–6, for column row–6, the next card from the deck to
   that column; the first card each column gets in its own row (its last) is face up.
5. The other 24 to the stock, in order, face down (the last is the stock's top).
6. Save `seed`, add 1 to `deals`, set `game_magic`; `store_close`.

For seed 0x1234 that gives (face down in brackets; T is ten):

```
1:  9C
2:  (4D) 2C
3:  (4H) (6C) 8D
4:  (8S) (TH) (9D) KS
5:  (AS) (4S) (3H) (7S) 2D
6:  (JH) (TS) (8H) (5H) (8C) QS
7:  (JD) (KC) (9H) (5S) (QD) (3D) 5C
stock: 24 cards, 3C on top
```

## 6. Drawing the layout (`ui.S`)

`ui_draw` draws the whole table from the piles, with step 3's `gfx` routines, as in the plan's Layout:

| What | Where | Drawn as |
| --- | --- | --- |
| Stock | column 0 of the top row (x 2, y 2) | a back if it has cards, else an empty slot |
| Waste | column 1 | its top card, else a slot |
| Foundations 1–4 | columns 3–6 | each top card, else a slot |
| Tableau 1–7 | columns 0–6 (x = 2 + 20 n), from y 30 | face-down cards as 3-line strips, face-up as 10-line strips, the last card whole |
| Status line | y 160 | the game number (`deals`), in the small font |

A deal's tallest column (6 face down and 1 face up) is 6 × 3 + 26 = 44 lines, far from the 128 available, so
the squeeze for long columns waits for step 7. Every routine marks its lines dirty, so `lcd_flush` sends the
screen. Step 7 will add redrawing just the piles a move changed; for now a new deal redraws everything.

## 7. `main`

From this step the default build is **the game** (`TEST_SCREEN` 0); the test screens stay available with 1–3.

- **Start-up:** `system`, `lcd`, `buttons`; then, if `game_magic` says there's a game, `ui_draw` it; if not,
  a title screen: "SOLITAIRE" and "PRESS NEW TO DEAL".
- **Events:** `B_NEW` → `game_new` (seeded from the press) and `ui_draw`. Every other role is ignored until
  step 6. (The plan's "press NEW twice to confirm" is step 8's; a game can't be lost yet, as there are no
  moves.)

## 8. Checking it

New tests in `tests/run.sh`, on a build with `-DTEST_SEED=0x1234`:

| Test | Checks |
| --- | --- |
| `step5_deal` (screen) | Press NEW once; the screen matches the approved picture `step5_deal.pbm` |
| `step5_deal piles` | The 13 piles, read from memory, are exactly what a reference deal in Python gives for that seed (a small `tests/deal.py`: the same xorshift, `rng_below`, shuffle and deal as sections 3–5) |
| `step5_deal cards` | Every card 1–52 is in exactly one pile, once; only each column's last card is face up; the counts are 24, 0, 0, 0, 0, 0, 1–7 |
| `step5_title` (screen) | A fresh build with no game shows the title screen |
| `step5_deal kept` | After a reset (`--pin 9=0@t --pin 9=1@t'`: RST, package pin 9, low and back high; driven high rather than released, as RST's pull-up is on the board), the same game is still there and drawn |

The Python reference makes the deal check exact without copying 52 numbers into the test: any mistake in the
shifts, the multiply, the shuffle or the deal order shows up as a difference, with the first wrong card named.
A second run with seed 0x5678 confirms a different seed gives a different deal.

In NetBeans: Run, then click NEW (or press A) a few times: a different game each time.

## Watch out for

- **`store_open` before writing a pile or using the generator, `store_close` after.** With PFWP set, writes to
  program FRAM are ignored, silently, so a forgotten `store_open` leaves the old game in place, or (for `rng`,
  also in `.persistent`) a generator stuck at 0 that never shuffles. A test that calls `rng_next` on its own
  needs `store_open` too.
- **`SYSCFG0` needs its password (`FRWPPW`)** in the high byte of every write, or the write is ignored.
- **32-bit shifts carry between the words:** `rla` the low word first, then `rlc` the high one; for right
  shifts, `clrc` then `rrc` the high word, then `rrc` the low one.
- **xorshift's state must never be 0** (it would stay 0): `rng_seed` turns 0 into 1.
- **The multiplier's operands:** write `MPY` (unsigned) first, then `OP2`, which starts the multiply; read
  `RESHI` after. An interrupt routine that used the multiplier would need to save its registers, so keep it out
  of interrupts.
- **The deck scratch space is RAM** (52 bytes of `.bss`); only the dealt piles are written to FRAM.
- **Each column's last card face up**, the rest face down: the first card a column gets in its own row.
