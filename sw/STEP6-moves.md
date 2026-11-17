# Step 6: moves

From the plan (`PLAN.md`, Milestones):

> **Moves**: rules, multi-card moves, stock and waste, automatic turn-over, win detection. Check: scripted games,
> including a full winning game from a known seed.

The goal: the game model can play Klondike. It applies a move when it's legal and refuses it when it isn't, moves
the right run of cards between columns, deals from the stock, turns uncovered cards face up, and knows when the
game is won. Every move produces a small record, for step 8's undo.

This step is the model (`game.S`); step 7 is the interface that drives it (`STEP7-interface.md`).

**Status: done.** All of it is in `game.S` and checked by `tests/run.sh`.

## 1. The rules (PLAN.md, Rules)

Standard Klondike. The defaults are **draw 3** and **unlimited passes** through the stock; the options screen
(step 8) changes them for the next game.

| Move | Legal when |
| --- | --- |
| **Stock** | The stock has cards: deal `draw` of them (or as many as are left) to the waste, face up. The stock is empty: turn the whole waste back over into the stock, face down, if the game's passes allow it |
| **To a foundation** | One card, the top of the waste, a column or another foundation. An empty foundation takes an ace; otherwise the same suit, one rank higher |
| **To a column** | From the waste or a foundation: its top card. From another column: the run that fits (below). The destination's top card is face up, one rank higher, the other colour; an empty column takes only a king |
| **Column to column** | Of the source's face-up cards, the one that fits the destination; it and every card on it move |

Then, automatically:

- **Turn-over:** a move that leaves a face-down card on top of a column turns it face up.
- **Win:** when all four foundations hold 13 cards.

**Colour:** bit 5 of a card (`HEARTS` 0x20 and `DIAMONDS` 0x30 have it; spades and clubs don't). Two cards are
the other colour when `(a ^ b) & HEARTS` is non-zero.

**Why only one card can fit:** a column's face-up cards always form a run (they only grow by legal moves, or start
as a single turned-over card), so among them each rank appears once and only one can be one lower than the
destination's top card. `game_move` looks from the top down and stops at the first face-down card.

## 2. The game's data (`store.S`, `.persistent`)

Beside the piles:

| Name | Size | Holds |
| --- | --- | --- |
| `moves` | word | Moves made this game: the status line; an undo takes one back |
| `draw` | byte | Cards a stock move deals, 1 or 3: copied from the options at `game_new`, so a game keeps its rules |
| `passes` | byte | Times the waste has been turned back over |
| `won` | byte | Non-zero once the game is won |
| `last_move` | 4 bytes | The latest change's record (section 3): what `ui.S` redraws |
| `max_passes`, `scoring`, `score` | | Step 8's pass limit and scoring |
| `undo_count`, `undo_next`, `undo_log` | | Step 8's undo log |

## 3. The move record

Four bytes, enough to undo the move exactly without a snapshot (`sol.h`: `M_SOURCE`, `M_DEST`, `M_COUNT`,
`M_FLAGS`):

| Byte | Holds |
| --- | --- |
| 0 | Source pile (`P_STOCK` … `P_TAB1 + 6`) |
| 1 | Destination pile |
| 2 | How many cards moved |
| 3 | Flags: `M_TURNED` the source's new top was turned face up; `M_RECYCLED` the waste was turned back into the stock |

A stock deal is recorded as source `P_STOCK`, destination `P_WASTE`, the count dealt; a turn-over of the waste as
source `P_WASTE`, destination `P_STOCK`, the count, and `M_RECYCLED`.

## 4. The routines (`game.S`)

Each routine that changes the game opens FRAM with `store_open` and closes it with `store_close` itself (which also
seals the game with its checksum: `STEP9-saving.md`). A refused move checks everything before its first write, so
it changes nothing.

| Routine | In | Out | Does |
| --- | --- | --- | --- |
| `card_fits` | R12 = card, R13 = pile | R12 = 1 or 0 | The rule check alone |
| `game_move` | R12 = source, R13 = destination | R12 = 1 moved, 0 refused | Any move but the stock's: finds the count (1, or the run), moves it, turns over, records it, checks for a win |
| `game_to_foundation` | R12 = the waste or a column | R12 = the foundation, or 0 | The top card to the first foundation that takes it (for the same button twice) |
| `game_stock` | | R12 = `STOCK_DONE`, `STOCK_NONE` (nothing to do) or `STOCK_LIMIT` (no passes left) | Deals, or turns the waste over |
| `game_undo` | | R12 = 1 or 0 | Step 8 |

Helpers: `pile_move` (moves a run keeping its order, through the scratch pile: two reversals make none),
`pile_deal` (moves cards one at a time, reversing them, turning each face up or down: the stock's deal and its
turn-over), `turn_over` and `turn_back`, `record_move` (the record into `last_move` and the undo log, the move
count and the score), `check_win` (sets `won` and counts it in the statistics).

**The stock's order:** dealing pops the stock's top and pushes it on the waste, so the last card dealt is the
waste's top, as by hand. Turning the waste over pops each card back onto the stock, so the first card dealt comes
back to the stock's top: the next pass deals in the same order.

## 5. Checking it

`tests/klondike.py` is a model of the whole firmware in Python: the deal (`deal.py`), the rules, the stock, undo,
scoring, the statistics and options, and what each button does (step 7's two presses). A test presses buttons in
the simulator, then dumps everything kept in FRAM and compares it with the model after the same presses, byte for
byte: every pile, the counts, the undo log, the score, the statistics, and the checksum.

| Test | What it plays |
| --- | --- |
| `step6_stock_turnover`, `step6_stock_second_pass` | Draw 3 through the whole stock, the turn-over, the next pass dealing the same cards (`tests/stock.py`) |
| `step6_moves` | 283 presses of real play from seed 0x1234 (`tests/moves.txt`): runs between columns, kings to empty columns, foundation cards back down, the stock, illegal tries, same-button doubles |
| `step6_win` | A whole winning game: seed 0x1007 in draw 1, 131 moves in 216 presses (`tests/win.txt`), ending with the win screen |

The scripted plays come from `tests/sequences.py`, which plays the model with a fixed random seed (mostly legal
moves, with illegal ones mixed in); the winning game from `tests/solve.py`, a depth-first solver whose moves are
turned into presses and replayed on the model before they're written. Both files are committed, so the tests
stay fixed.

## Watch out for

- **`store_open` before changing anything, `store_close` after.** Forgetting `store_open` loses the writes
  silently (FRAM stays protected).
- **Never pop an empty pile:** `pile_pop` doesn't check. Check the count first.
- **A run keeps its order** (`pile_move`); **the stock deal and the turn-over reverse, on purpose** (`pile_deal`).
- **`last_move` is at an odd address**, so the record is copied byte by byte, never as words.
- **A foundation card can come back to a column**; that's legal, and some games need it.
