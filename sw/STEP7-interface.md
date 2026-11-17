# Step 7: the interface

From the plan (`PLAN.md`, Milestones):

> **Interface**: two-press moves, selection display, same-button-twice to foundation, status line, layout
> compression of long columns, win screen.

The goal: the game can be played on the buttons, with the screen showing what's selected, saying when a move isn't
allowed, and redrawing only what changed.

**Status: done.** In `ui.S`; checked by `tests/run.sh` (pictures, and FRAM against the model).

## 1. What each button does (`ui_button`)

| Button | With nothing selected | With a pile selected |
| --- | --- | --- |
| A column, the waste or a foundation | Selects it (its top card is drawn inverted), if it has a card; else says NOTHING THERE | The same pile: its top card to a foundation if one takes it (else only deselects). Another pile: moves there if the rules allow, and deselects; if not, says CAN'T GO THERE and keeps the selection |
| STOCK | Deals, or turns the waste over; says NO PASSES LEFT if the pass limit stops it | The same, after deselecting |
| UNDO | Takes back the last move (step 8); says NOTHING TO UNDO if there's none | The same, after deselecting |
| NEW | Deals at once if no move has been made; else says PRESS NEW AGAIN FOR A NEW GAME, and a second NEW deals (any other button in between cancels) | The same, after deselecting |
| OPTIONS | Opens the options screen (step 8) | The same, after deselecting |

Before there's a game (the title screen), and once a game is won (the win screen), only NEW and OPTIONS do
anything, and NEW deals without asking.

A message shows for one press: white on black across the status line. The selection, the NEW question and the
screen in use are RAM (`sel`, `confirm`, `mode`), so a reset forgets them; the game itself is in FRAM.

## 2. The screen (PLAN.md, Layout)

```
y 2     [stock] [waste]    [ F1 ] [ F2 ] [ F3 ] [ F4 ]     top row: cards 19 x 26
y 30    [T1]  [T2]  [T3]  [T4]  [T5]  [T6]  [T7]           the tableau, to y 157
y 159   MOVES n      SCORE n                  DRAW n       the status line, lines 159-167
```

- **The waste**: its top card; in draw 3 its top three fanned 9 pixels apart (each showing its rank and suit), the
  top one whole. It uses columns 1 and 2, as nothing else sits in column 2.
- **The selection**: the source's top card inverted (`SELECTED` in `gfx_card`). For a column that's its last card:
  which run moves isn't known until the destination is pressed.
- **The status line**: MOVES n; SCORE n (signed) with scoring on; DRAW n at the right. A message replaces it.
- **The win screen**: a framed box over the table: YOU WIN!, the moves, the score with scoring on, WON n OF n,
  and PRESS NEW TO DEAL AGAIN. It stays (also after a reset) until NEW.

### Squeezing a long column

The tableau has 128 lines. A column normally shows its face-down cards as 3-line strips, its face-up ones as
10-line strips and its last card whole (26). `draw_column` works out what it needs and squeezes only as far as
necessary: first the face-down strips, down to 1 line; then the face-up ones, down to 8. The tallest legal column
(6 face down, 13 face up) then takes 6 + 12 × 8 + 26 = 128 lines, an exact fit.

At 1 line each, face-down strips merge into a solid bar: they show that there are face-down cards, but not how many
(that would take 2 lines each, which the tallest column hasn't room for). Columns that tall are rare.

## 3. Redrawing only what changed (`ui_update`)

Each press sets bits in `redraw`: a bit per pile, `R_STATUS`, or `R_ALL`.

- A selection or deselection marks that pile.
- A move, deal or undo marks the two piles in `last_move` (`game_undo` leaves the undone record there).
- The status line is redrawn on every press.
- A new game, the win, closing the options screen, or start-up mark everything.

Every line drawn has to be sent to the display, at about 160 µs a line, with the CPU waiting. So a column remembers
how far down it was drawn (`col_bottom`) and a redraw clears only those lines, not all 128. That halved the cost of
a press: about 92,000 cycles (11 ms) on average over real play (`step10_press`).

## 4. Checking it

Pictures, against approved ones, each with FRAM checked against the model too:

| Test | Presses (seed 0x1234) | Shows |
| --- | --- | --- |
| `step7_select` | NEW T7 | Column 7's top card (5♣) inverted |
| `step7_cant` | NEW T1 T2 | 9♣ can't go on 2♣: the message, and column 1 still selected |
| `step7_waste` | NEW STOCK STOCK WASTE | Draw 3: the top three fanned, the top one selected |
| `step7_confirm` | NEW STOCK NEW | The question for a new game mid-game |
| `step7_squeeze` | (a made-up game: `-DTEST_SCREEN=4`, `testsqueeze.S`) T4 | Every column height that matters, the tallest one selected |
| `step6_win` | the winning game | The win screen |

Every scripted play (steps 6 and 8) goes through these same two-press rules, so they're checked against the
model hundreds of times over.

## Watch out for

- **Registers across calls**: `ui_button` keeps the role or pile in R10 (saved); everything else it calls changes
  R11-R15.
- **Long jumps to other files**: `jmp` reaches only ±1 KB, so tail calls to `gfx.S` use `br #routine`.
- **A pile's place must be cleared before it's redrawn**: `gfx_card` paints its own rectangle, but a shorter pile
  must not leave the old one's cards showing below it (the waste's 2 columns, `col_bottom` for columns).
