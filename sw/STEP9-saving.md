# Step 9: saving

From the plan (`PLAN.md`, Milestones):

> **Saving**: FRAM write protection discipline, version and checksum, resume after power-up (in the simulator:
> reset mid-game and check the game is back).

The game has lived in FRAM since step 5, so it already survives a reset. This step makes sure that what comes
back is a game the firmware can trust.

**Status: done.** In `store.S`, `ui_start` (`ui.S`) and `system.S`; checked by `tests/run.sh`.

## 1. What's kept (`store.S`, `.persistent`, 1320 bytes)

| Block | Holds | Trusted by |
| --- | --- | --- |
| The game | `game_magic`, the seed and generator, `deals`, the 13 piles, the counts and rules, `last_move`, the score, the undo log, `game_version` | `game_sum`, its checksum |
| Settings and statistics | The options, played, won, streak, best, watchdog resets | `settings_magic` and range checks |

They're separate so that a lost game never loses the statistics.

## 2. Write protection

`SYSCFG0.PFWP` protects program FRAM (code, constants and `.persistent` alike). Every change is bracketed:

- `store_open` lifts the protection;
- `store_close` works out the game's checksum, stores it in `game_sum`, and protects FRAM again;
- `store_protect` protects FRAM again without touching the checksum: for the settings, statistics and the watchdog
  count.

So the program is only writable for the few instructions of a change, and a stray write elsewhere is ignored.

## 3. The checksum and version

`store_sum` runs over the words from `game_magic` to `game_version` (651 words): `sum = (sum rotated left 1) +
word`. The rotation makes the order count, so two swapped words change it. It takes about 1 ms at 8 MHz, once per
change.

`game_version` is `STORE_VERSION` (now 2). A game saved by firmware with a different layout is dropped rather than
misread. (Programming the chip normally reloads `.persistent` anyway; this guards against tools that don't.)

## 4. At start-up (`ui_start`)

1. `settings_valid`: the settings and statistics, or the defaults.
2. `store_valid`:
   - `game_magic`, `game_version` and the checksum all right: **resume** the game exactly (the win screen too, if
     it was won).
   - The checksum is wrong (the batteries came out between a change and its seal), but the piles hold each of the
     52 cards exactly once, with every count in range (`cards_valid`): **keep the game**, but clear its undo log
     (its records may not match), and seal it.
   - Otherwise: **drop it** (clear `game_magic`) and show the title screen.
3. The selection, the NEW question and the screen in use are RAM: a reset forgets them.

`system` also reads `SYSRSTIV` at start-up: a reset by the watchdog (0x16, a hang it caught) is counted in
`wdt_resets` and shown on the options screen.

## 5. Checking it

| Test | Does | Expects |
| --- | --- | --- |
| `step9_before` / `step9_resume` | Plays a few presses; the same again, then a reset | The same picture, and FRAM as the model |
| `step9_damaged_count` | A `-DTEST_CORRUPT=1` build: the move count changed after the seal; then UNDO | The game kept, with the count as damaged, and no undo (NOTHING TO UNDO) |
| `step9_damaged_cards` | A `-DTEST_CORRUPT=2` build: a card doubled | The title screen; the statistics kept |

`TEST_CORRUPT` damages the kept game at every start (only when there is one), as a power cut mid-change might.

## Watch out for

- **Never seal from start-up code**: `system` runs before `store_valid` and uses `store_protect`, or it would seal a
  half-changed game as good.
- **Add to the game's data before `game_version`**: the checksum covers up to it. Then raise `STORE_VERSION`, and
  move `game_sum`'s position in `tests/klondike.py`'s image.
