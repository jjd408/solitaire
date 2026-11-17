# Step 8: undo, new game, options

From the plan (`PLAN.md`, Milestones):

> **Undo, new game, options**: the undo log, confirm for new game, the options screen (draw 1/3, stock passes,
> scoring, statistics).

**Status: done.** Undo and scoring in `game.S`, the options screen in `options.S`, the data in `store.S`; checked by
`tests/run.sh`.

## 1. The undo log

A ring of `UNDO_SIZE` (256) move records in `.persistent` (1 KB), so undo goes back 256 moves, across power loss
too. `undo_next` is where the next record goes (a byte: 255 + 1 is 0, which goes round the ring); `undo_count` is
how many are there, up to 256 (past that the oldest is overwritten).

`record_move` writes each record into `last_move` and the log. `game_undo` takes the newest back off and undoes it
exactly:

| The record | Undone by |
| --- | --- |
| A move (any `game_move`) | Turning the source's top card back down if `M_TURNED`, then moving the cards back in order (`pile_move` from destination to source) |
| A deal from the stock | Dealing the cards back onto the stock, face down (`pile_deal` reverses them back) |
| The waste turned over (`M_RECYCLED`) | Dealing the stock back out onto the waste, face up; one pass fewer |

The move count goes back by one and the score by the move's worth (`score_delta`, worked out from the record, so
it needs no storing). A won game can't be undone (the win is already counted in the statistics), and an empty
log says NOTHING TO UNDO.

## 2. New game

NEW mid-game asks first (`STEP7-interface.md`). `game_new` then:

- counts the game in the statistics: one more played, and the streak ends if the game before wasn't won;
- copies the options into the game's rules (`draw`, `max_passes`, `scoring`), so a game keeps the rules it was dealt
  with even if the options change during it;
- starts the counts: moves, passes, won, the score (Vegas: −52), an empty undo log;
- shuffles and deals as before, and seals the game (`STEP9-saving.md`).

## 3. Scoring

| | Standard | Vegas |
| --- | --- | --- |
| Start | 0 | −52 (the deck's price) |
| Waste to a column | +5 | |
| Waste or a column to a foundation | +10 | +5 |
| A foundation card back to a column | −15 | −5 |
| A card turned over | +5 | |
| The waste turned over | −100 in draw 1 | |

There are no time bonuses (there's no clock running while you think). The score can go below 0, so undo stays
an exact inverse.

## 4. The options screen (`options.S`)

OPTIONS opens it in place of the game; OPTIONS again goes back to the game (or the title screen) as it was. Each
setting sits beside a suit button, which steps through its values:

| Button | Setting | Values |
| --- | --- | --- |
| S1 | Draw | 3 cards, 1 card |
| S2 | Stock passes | Unlimited, 3, 1 (a pass is a time through the stock: 3 passes allow 2 turn-overs) |
| S3 | Scoring | Off, standard, Vegas |
| S4 | Reset statistics | Press twice: the first press asks (PRESS AGAIN TO RESET) |

Below, the statistics: played, won (with the rate, `percent`: the hardware multiplier for part × 100, then repeated
subtraction), the streak, the best streak, and the watchdog resets if there were any (`STEP9-saving.md`).

The settings and statistics live apart from the game in `.persistent`, with their own `settings_magic`;
`settings_valid` puts the defaults back if that's wrong or a setting is out of range.

## 5. Checking it

Against the model (`tests/klondike.py`), byte for byte, including the undo log and score:

| Test | Plays |
| --- | --- |
| `step8_undo` | 120 steps of play with undos mixed in, then undo back to the deal and two more (`tests/undo.txt`) |
| `step8_standard`, `step8_vegas` | Play with undos under each scoring (`tests/standard.txt`, `vegas.txt`) |
| `step8_passes` | One pass in draw 1: the stock runs out and won't turn over; undo and deal again (`tests/passes.txt`) |
| `step8_options` | Every setting changed, and S4's question; with the picture |

## Watch out for

- **Settings changes use `store_protect`, not `store_close`**: closing would seal the game, which must stay
  unsealed if a power cut left it half-changed (`STEP9-saving.md`).
- **The ring's index is a byte on purpose**: `inc.b` and `dec.b` wrap it at 256 for free. Changing `UNDO_SIZE`
  means masking it instead.
