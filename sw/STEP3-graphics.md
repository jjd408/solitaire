# Step 3: graphics

From the plan (`PLAN.md`, Milestones):

> **Graphics**: font and suit glyphs, card faces, backs, empty slots, inverted selection, text. Check: a sheet
> of all 52 cards.

## Files

| File | Holds |
| --- | --- |
| `font.S` | The glyphs, as constants in FRAM: a 5 × 7 font (space to Z), the ranks (with a narrow 10), small and big suits |
| `gfx.S` | Drawing into `fb`: rectangles, glyphs, text, numbers, cards, empty slots |
| `testcards.S` | `card_sheet`, the step 3 test screen |
| `sol.h` | Display and card constants: `LCD_W`, `LCD_H`, `LINE`, `CARD_W`, `CARD_H`, `FACE_UP`, `SELECTED`, the suits |

## Drawing routines (`gfx.S`)

All of them follow the plan's conventions (arguments in R12–R15, R11–R15 may change) and mark the lines they
change in `dirty`, so the next `lcd_flush` sends exactly those. Coordinates are pixels, x 0–143, y 0–167.

| Routine | In | Draws |
| --- | --- | --- |
| `gfx_clear` | | The whole screen white, every line dirty |
| `gfx_black`, `gfx_white`, `gfx_invert`, `gfx_checker` | R12 x, R13 y, R14 width, R15 height | A filled rectangle; `gfx_invert` flips what's there; `gfx_checker` is a 50% checkerboard |
| `gfx_glyph` | R12 x, R13 y, R14 glyph | One glyph in black; returns R12 = x + width + 1 |
| `gfx_text` | R12 x, R13 y, R14 text (ends in 0) | Text, 6 pixels a character, lower case as upper; returns R12 after it |
| `gfx_number` | R12 x, R13 y, R14 number | 0–65535 in decimal; returns R12 after it |
| `gfx_card` | R12 x, R13 y, R14 card, R15 lines showing | A card (or its top R15 lines, where the next card covers the rest) |
| `gfx_slot` | R12 x, R13 y | An empty pile: a dotted outline |
| `gfx_mark` | R12 first line, R13 lines | Marks lines dirty (for drawing done some other way) |

**`gfx_card`**: the card byte is the game's (rank in bits 0–3, suit in bits 4–5, `FACE_UP`), plus `SELECTED`
(bit 6, never stored in a pile) to draw it inverted. A face has the rank and a small suit at the top left and a
big suit in the middle; a back is the outline around a checkerboard. R15 is the strip height from the layout:
3 for a face-down card in a column, 10 for a face-up one, `CARD_H` (26) for the last card. Draw a column from
the top down, so each card's strip covers the one above.

**How a card is 19 × 26:** outline 1 pixel with the corner pixels left out; rank at (x+2, y+2), up to 7 wide;
small suit at (x+12, y+2); big suit 9 wide at (x+5, y+13).

**Clipping:** nothing is drawn at or below `clip_bottom` (normally 168), which is how `gfx_card` draws only a
strip. Nothing is drawn past the right edge: a glyph that doesn't fit is left out.

## Inside

- **Rectangles** work a byte at a time: per line, a first byte masked from x on, whole bytes, and a last byte
  masked up to the right edge (`left_mask`, `right_mask`). The columns are at x = 2, 22, 42 ... (the plan's
  layout), which aren't on byte boundaries, so this matters.
- **Glyphs**: each row is shifted left by x % 8 into a 24-bit value (`rla`/`rlc` through two registers) and
  cleared out of three fb bytes with `bic.b`.
- **Font data** is written as pixel art with a macro: `row .###.` assembles to `.byte 0x0E` (bit 0 is the
  leftmost pixel). Rows wider than 8 become words. To change a glyph, edit its art.

## The test

`main.S` shows the card sheet by default (`TEST_SCREEN` 2); `-DTEST_SCREEN=1` brings back step 2's pattern.
`tests/run.sh` builds both and checks each against its approved picture (`step2_pattern.pbm`,
`step3_cards.pbm`).

The sheet: a back, an empty slot, the ace of spades selected and the four kings across the top; all 52 cards
in seven columns below, each column starting with face-down strips as in the game; then the whole font and two
numbers.

## For later

- **8-line strips** (the plan's squeeze for very long columns): the rank and suit start 2 lines below a card's
  top edge, so in an 8-line strip their bottom line falls under the next card's edge. Either start them 1 line
  down when a column is squeezed, or squeeze to 9 and find the space elsewhere. To decide in step 7, with a real
  tall column on screen.
- **Speed**: drawing the whole sheet (59 cards, all the text) takes about 290,000 cycles, 36 ms at 8 MHz, on
  top of the 27 ms to send a full screen. Redrawing the one or two piles a move changes is a few milliseconds.
