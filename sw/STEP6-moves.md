# Step 6: moves

From the plan (`PLAN.md`, Milestones):

> **Moves**: rules, multi-card moves, stock and waste, automatic turn-over, win detection. Check: scripted games,
> including a full winning game from a known seed.

The goal: the game model can play Klondike. It applies a move when it's legal and refuses it when it isn't, moves
the right run of cards between columns, deals from the stock, turns uncovered cards face up, and knows when the
game is won. Every move produces a small record, ready for step 8's undo.

This step is the model; step 7 is the interface (selection shown inverted, same-button-twice to a foundation,
messages, the squeeze for long columns, the win screen). To play in the simulator before then, section 6 adds
plain two-press controls.

## 1. The rules (PLAN.md, Rules)

Standard Klondike, long-standing defaults: **draw 3**, **unlimited passes** through the stock (your choices; the
options screen in step 8 will change them).

| Move | Legal when |
| --- | --- |
| **Stock** | The stock has cards: deal 3 (or as many as are left) to the waste, face up. The stock is empty: turn the whole waste back over into the stock, face down |
| **To a foundation** | One card, the top of the waste, a column or another foundation. An empty foundation takes an ace; otherwise the same suit, one rank higher |
| **To a column** | From the waste or a foundation: one card. From a column: a run (below). The destination's top card is face up, one rank higher, the other colour; an empty column takes only a king (or a run starting with one) |
| **Column to column** | The run that fits: of the source's face-up cards, the one whose card is one lower and the other colour than the destination's top (or a king for an empty column); it and everything on it move |

Then, automatically:

- **Turn-over:** a move that leaves a face-down card on top of a column turns it face up.
- **Win:** when all four foundations hold 13 cards.

**Colour:** bit 5 of a card (`HEARTS` 0x20 and `DIAMONDS` 0x30 have it; spades and clubs don't). Two cards are
"the other colour" when `(a ^ b) & HEARTS` is non-zero.

**Why a column's face-up cards are always a valid run:** they only ever grow by legal moves onto them, or by a
turn-over that leaves one face-up card. So the run to move is found by looking for one card, never by checking a
sequence.

## 2. The game's data (`store.S`, `.persistent`)

Added beside the piles:

| Name | Size | Holds |
| --- | --- | --- |
| `moves` | word | Moves made this game, for the status line |
| `draw` | byte | Cards a stock move deals: 3 (1 once options exist), copied at `game_new` so a game keeps its rules |
| `passes` | byte | Times the waste has been turned over (for a pass limit later; unlimited for now) |
| `won` | byte | Non-zero once the game is won |
| `last_move` | 4 bytes | The latest move's record (section 3); step 8 replaces it with the undo log |

`game_new` sets them: `moves` 0, `draw` 3, `passes` 0, `won` 0.

## 3. The move record

Four bytes, as the plan designed, so step 8 can undo a move exactly without a snapshot:

| Byte | Holds |
| --- | --- |
| 0 | Source pile (`P_STOCK` … `P_TAB1 + 6`) |
| 1 | Destination pile |
| 2 | How many cards moved |
| 3 | Flags: `M_TURNED` (bit 0) the source's new top was turned face up; `M_RECYCLED` (bit 1) the waste was turned back into the stock |

A stock deal is recorded as source `P_STOCK`, destination `P_WASTE`, the count dealt; a recycle as source
`P_WASTE`, destination `P_STOCK`, the count, and `M_RECYCLED`.

## 4. The routines (`game.S`)

All change FRAM, so each opens it with `store_open` and closes it with `store_close` (the pile routines need it).

| Routine | In | Out | Does |
| --- | --- | --- | --- |
| `game_stock` | | R12 = 1 done, 0 nothing to do | Deals `draw` cards from the stock to the waste, face up; or, with the stock empty, turns the waste over into it, face down |
| `game_move` | R12 = source pile, R13 = destination pile | R12 = 1 moved, 0 refused | Any move of section 1 but the stock's; finds the run, moves it, turns over, counts it, records it, checks for a win. A refused move changes nothing |
| `game_to_foundation` | R12 = source pile | R12 = the foundation it went to, or 0 | Moves the source's top card to whichever foundation takes it (for step 7's same-button-twice) |
| `card_fits` | R12 = card, R13 = destination pile | R12 = 1 or 0 | The rule check alone, for `game_move` and for step 7's hints |

Helpers worth having, as the rules use them over and over: `card_rank` (`and.b #RANK_MASK`), `card_red`
(`bit.b #HEARTS`), and `pile_take(source, count, destination)`, which moves the top *count* cards keeping their
order (pop them onto a small RAM stack, then push them back off it: two reversals make no reversal).

**Moving cards with their order:** a run of 4 from column 3 to column 6 must arrive in the same order. Popping
them one at a time straight onto column 6 would reverse them; going through a scratch buffer of 13 bytes keeps
them in order. (The stock deal *does* want each card pushed as it's popped: the last card dealt is the waste's top,
as when dealing by hand. And the recycle wants the reversal too: popping the waste onto the stock puts its
bottom card on the stock's top, restoring the stock's order.)

## 5. Drawing

`ui_draw` from step 5 draws whatever the piles hold, so after each move `main` calls it to redraw the whole
table. Step 7 changes that to redrawing only the piles a move touched. Two additions to the drawing now:

- **The waste in draw 3:** its top 3 cards fanned across (each showing its left 6 pixels, the top one whole),
  so you can see what's coming; step 7 may tidy it.
- **The status line:** `MOVES n`, and `YOU WIN` once `won` is set (step 7 adds the real win screen).

## 6. Temporary controls, until step 7

So the game can be played in the simulator now, `ui_button` grows plain two-press moves:

- **Stock** (B_STOCK): `game_stock` at once.
- **Any pile button:** the first press chooses the source; the second chooses the destination and calls
  `game_move` (or `game_to_foundation` if the same button is pressed twice). An illegal move does nothing.
- **NEW:** a new game, as now.

The chosen source isn't shown yet (step 7 draws it inverted), and nothing is said about refused moves. A RAM byte,
`pending`, holds the source between the presses (0: none chosen).

## 7. Checking it

A Python reference model, `tests/klondike.py`, extends `deal.py`: the same deal, then the same rules, so any
sequence of moves can be checked exactly against the piles read back from FRAM, as step 5 checks the deal.

**Scripted move tests** (in `run.sh`), each a list of moves pressed with the buttons (`--pin`), from a fixed seed:

| Test | Checks |
| --- | --- |
| Legal single moves | Waste to column, column to foundation, foundation back to a column |
| A run between columns | The right card chosen, the run moved in order |
| A king to an empty column | Accepted; a non-king refused |
| Turn-over | The uncovered card face up, `M_TURNED` in the record |
| Illegal moves | Wrong colour, wrong rank, a non-ace to an empty foundation: the piles unchanged, byte for byte |
| The stock, draw 3 | Deals of 3, a short last deal, the recycle restoring the stock's order |
| The stock, draw 1 | The same with a `-DTEST_DRAW=1` build |

After each, the piles in FRAM must match what `klondike.py` gives for the same moves, and the screen an approved
picture.

**A full winning game.** `tests/solve.py` searches a few seeds for one it can win with draw 1 (a simple depth-first
search with the usual tricks: aces and twos to foundations first, no undoing the last move) and writes the moves.
The test plays them all and checks: every foundation has 13 cards, `won` is set, the status line says `YOU WIN`,
and the move count matches. With a hundred or so moves at two presses each, this is the longest test, so it runs
without the display model except for one picture at the end.

**Fast checks without the buttons:** a `-DTEST_MOVES` build can play a move list compiled into the firmware
straight through `game_move`, testing the model alone in a fraction of a second of simulated time; useful for the
long winning game and for finding a bug quickly.

## Watch out for

- **`store_open` before changing piles**, `store_close` after: a forgotten one leaves the old game silently.
- **Never pop an empty pile:** `pile_pop` doesn't check. Check the count first (a refused move must change nothing).
- **A run keeps its order:** move it through a scratch buffer (section 4).
- **The stock deal and the recycle do reverse, on purpose.**
- **Turn the new top over only if it's face down,** and only for a column (the waste and foundations are always
  face up).
- **A foundation card can come back to a column**; that's legal, and some games need it.
- **A refused move changes nothing**, not even `moves` or `last_move`: check everything before the first write.
- **Register discipline:** `game_move` calls the pile routines in loops, so keep its working values in R4–R10 and
  save them.
- **Capacity:** a column holds up to 19 cards and the waste 24; the rules can't exceed them, but a bug could, so
  the tests check counts.
