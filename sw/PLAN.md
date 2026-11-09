# Solitaire firmware plan

The firmware for the handheld in `hw/`: an MSP430FR2355 playing Klondike solitaire on a Sharp LS013B7DH05
memory LCD, with 16 buttons, sleeping between presses. It's written in assembly (GNU `as` syntax, `.S` files
through the C preprocessor so TI's register names from `msp430.h` work) in the NetBeans MSP430 project
`sw/sol`, and developed in the simulator (`sim/picsimlab-msp430`, Solitaire board) until boards exist.

This plan sets out the architecture, the decisions it rests on, and the order to build it in. Decisions still
open are collected at the end.

## What the firmware drives

All from `hw/sol/sol.kicad_sch`; the simulator's Solitaire board is wired the same way.

| Function | Pin | Peripheral | Notes |
| --- | --- | --- | --- |
| Display SCLK | P4.5 | UCB1CLK | SPI mode 0, LSB first, at most 1.1 MHz |
| Display SI | P4.6 | UCB1SIMO | |
| Display SCS | P4.7 | GPIO | Active high; not UCB1STE (that's P4.4) |
| Display EXTCOMIN | P5.0 | TB2.1 | 57–66 Hz, must run whenever DISP is high |
| Display DISP | P5.1 | GPIO | High = display on |
| Stacks 1–4 | P1.0, P1.1, P1.2, P1.3 | Port 1 interrupt | All buttons switch to ground; use internal pull-ups |
| Stacks 5–7 | P1.4, P1.5, P1.6 | Port 1 interrupt | |
| Stacks 8–9 | P2.0, P2.1 | Port 2 interrupt | |
| Suits 1–4 | P2.2, P2.3, P2.4, P2.5 | Port 2 interrupt | |
| SW1, SW2, SW3 | P3.0, P3.1, P3.2 | Port 3 interrupt | Below the stacks row |
| Programming | TEST, RST | Spy-Bi-Wire | RST has a 47 kΩ pull-up and 1 nF |

Unused pins (P1.7, P2.6, P2.7, P3.3–P3.7, P4.0–P4.4) are set as outputs driven low, the lowest-current state
for an unconnected pin. There's no crystal (P2.6/P2.7 are free), no LED, and no battery-voltage input.

Memory: 32 KB FRAM at 0x8000–0xFFFF (code, constants, and data that must survive power loss), 4 KB RAM at
0x2000–0x2FFF, 512 bytes of information FRAM at 0x1800.

## Tools and workflow

- **Edit, build, run, debug** in NetBeans with the MSP430 Assembly plugin: open `sw/sol`, **Build** (F11) makes
  `build/sol.hex`, **Run** (F6) starts it on PICSimLab's Solitaire board, **Debug** (Ctrl+F5) stops at
  breakpoints and shows the registers and every peripheral register. The machine-code column and the
  MSP430 Documentation window help while writing.
- **Automated tests** with the simulator's command-line runner `msp430_run` (in
  `sim/picsimlab-msp430/src/sim_backend/msp430/tests`): it presses buttons at given times (`--pin`), reads
  memory at the end (`--peek`), connects the display model and saves the screen as an image (`--sharp`), so a
  test can check the game state and compare the screen with an approved picture. See Testing below.
- **Reference code**: `sharp.c` and `buttons.c` in the same tests folder are working C versions of the
  display driver and button handling on these exact pins; port their sequences rather than re-deriving them.
- **Hardware**, later: an eZ-FET (LaunchPad) or MSP-FET on the Spy-Bi-Wire header, with mspdebug (its source is in
  `~/ti/src/mspdebug`, not built yet).

## Architecture

### Clocks and power

| Clock | Source | Rate | Used for |
| --- | --- | --- | --- |
| MCLK, SMCLK | DCO with the FLL, referenced to REFO | 8 MHz | CPU; SPI (SMCLK / 8 = 1 MHz) |
| ACLK | REFO in low-power mode (`CSCTL3.REFOLP`) | 32768 Hz | EXTCOMIN, button debounce, idle timing |

- **REFO, not VLO, for ACLK.** There's no crystal, and VLO's frequency varies too much to keep EXTCOMIN
  inside 57–66 Hz. REFO's calibrated tolerance is ±3.5% (EXTCOMIN 57.9–62.1 Hz) and in its low-power mode it
  draws about 1 µA (15 µA in high-power mode), from the datasheet's Table 5-7.
- **8 MHz** needs no FRAM wait state (above 8 MHz it does, and the simulator warns if it's missing). The CPU only
  runs for a few milliseconds per button press, so speed costs almost nothing in battery life.
- **Sleep in LPM3** between events: CPU, MCLK and SMCLK off, ACLK running EXTCOMIN. About 1 µA (datasheet
  Table 5-7, LPM3 with VLO) + 1 µA REFO + the display's static current (Sharp's DH05 spec leaves it "TBD"; this
  family is a few µW) + 75 nA for the regulator. Two AA cells would last years at that rate. LPM3.5/4.5 can't be
  used while the display is on, because they stop the timers and so EXTCOMIN.
- **No deep sleep**: the display stays on and the game stays visible all the time. Turning it off after a long
  idle would save only a couple of µA.

### Event loop

Everything happens in interrupts that set flags and wake `main`; `main` handles events and goes back to sleep.

```
main:   init clocks, ports, timers, SPI, display
        load or deal a game; draw everything
loop:   kick the watchdog
        disable interrupts
        if no events pending: enter LPM3 with GIE set   ; bis #LPM3_bits|GIE, SR (atomic, no lost wake-up)
        enable interrupts
        take the next event (button number)
        update the game; redraw what changed; send changed lines
        jmp loop
```

Interrupt routines end with `bic #LPM3_bits, 0(SP)` when they queue an event, so `reti` returns to `main`
awake. The event queue is a small ring buffer in RAM (16 entries is plenty).

### Interrupts

| Vector | Section (TI's linker script) | Does |
| --- | --- | --- |
| PORT1, PORT2, PORT3 | `__interrupt_vector_port1`, `_port2`, `_port3` | Read PxIV, queue the button, start its debounce lockout |
| TIMER0_B0 | `__interrupt_vector_43` | Debounce: re-enable buttons whose lockout ended |
| TIMER0_B1 | `__interrupt_vector_42` | TB0 overflow every 128 s: read TB0IV, wake `main` so it kicks the watchdog |
| (TB2.1 output) | none | EXTCOMIN toggles in hardware, no interrupt |

In assembly a vector is a word in its section:

```
        .section __interrupt_vector_port1,"ax",@progbits
        .word   port1_isr
```

The reset vector and start-up (`__crt0_start`, which clears `.bss`, copies `.data` and calls `main`) come from
gcc's start-up code, which the plugin links in.

### Watchdog

The watchdog is kept as a safety net: if the firmware ever hangs, the chip resets, and because the game lives
in FRAM it comes back where it was.

- **Clocked from ACLK** (REFO), with a time-out of 2^23 counts = 256 s:
  `WDT_RUN = WDTPW|WDTSSEL__ACLK|WDTIS__8192K|WDTCNTCL`. Not SMCLK: in watchdog mode the chip keeps the
  watchdog's clock running even in LPM3, so on SMCLK it would keep the DCO running and the sleep current would
  go from about 2 µA to hundreds (TI's family user's guide warns of exactly this). ACLK runs in LPM3 anyway.
- **Stopped during set-up**: `sys_init` writes `WDTPW|WDTHOLD` first (the watchdog runs from reset and would
  otherwise reset the chip after about 31 ms on the reset clocks) and `WDT_RUN` last.
- **Kicked on every pass of the main loop** by writing `WDT_RUN` again (always the whole word with the password:
  a write without `WDTPW` resets the chip).
- **Kept kicked while idle**: it counts on in LPM3, so the loop must run at least every 256 s even with no
  presses. TB0 runs from ACLK ÷ 64 (`ID__8` and `TBIDEX__8`, 512 Hz) in continuous mode; its overflow every
  65536 / 512 = 128 s raises `TBIFG` (enabled with `TBIE`, vector TIMER0_B1), which wakes `main` for one pass.
  That's one brief wake-up every two minutes.
- **After a watchdog reset** `SYSRSTIV` reads 0x16; `sys_init` counts these in `.persistent` (shown with the
  statistics), so a hang that's otherwise invisible gets noticed.

### Modules

One file per module under `sw/sol/src/`, each exporting a few routines (`.global`). The plugin builds all of
them into one program.

| File | Responsibility | Main routines |
| --- | --- | --- |
| `main.S` | Start-up, event loop | `main` |
| `system.S` | Watchdog (safety net), clocks (FLL to 8 MHz, REFO LP), TB0 time base, port defaults, LOCKLPM5 | `sys_init`, `wdt_kick` |
| `lcd.S` | SPI, SCS timing, all-clear, multi-line write of dirty lines, EXTCOMIN timer, DISP | `lcd_init`, `lcd_clear`, `lcd_flush` |
| `gfx.S` | Framebuffer drawing: fill, invert, glyphs, text, cards, dirty-line marking | `gfx_card`, `gfx_text`, `gfx_fill`, ... |
| `font.S` | Rank and suit glyphs, a small text font, card back pattern (FRAM constants) | data only |
| `buttons.S` | Port set-up, interrupt routines, debounce, event queue | `btn_init`, `btn_next` |
| `rng.S` | Pseudo-random numbers (xorshift32) and seeding | `rng_seed`, `rng_next` |
| `game.S` | Klondike model: deal, legal moves, applying and undoing moves, win check | `game_new`, `game_move`, `game_undo` |
| `ui.S` | What a button means in the current state, selection, layout, what to redraw | `ui_button`, `ui_draw` |
| `store.S` | FRAM write-protection discipline, validating the saved game | `store_open`, `store_close`, `store_valid` |

### Conventions

Follow msp430-gcc's calling convention, so routines could later be called from C (or C from assembly) and
gdb's backtraces make sense:

- Arguments in R12, R13, R14, R15; results in R12 (and R13).
- R4–R10 are preserved by the routine that's called (push and pop the ones it uses); R11–R15 may be changed.
- Small code model: all code lives in 0x8000–0xFFFF, so `call`/`ret` with 16-bit addresses, never `calla`.
- Each routine has a comment block stating inputs, outputs and registers changed.
- Constants in FRAM (`.section .rodata`), working data in RAM (`.bss`), saved data in `.persistent`.
- `.S` files `#include <msp430.h>` and use TI's names (`UCB1CTLW0`, `BIT5`, `OUTMOD_4`), never raw addresses.

### Memory budget

| Region | Use | Size |
| --- | --- | --- |
| FRAM, code | All modules | ~6–8 KB estimated |
| FRAM, constants | Font, suit glyphs, card back, text | ~1–2 KB |
| FRAM, `.persistent` | The game (piles, undo log, options, statistics, seed) | ~1.5 KB |
| RAM | Framebuffer 168 lines × 18 bytes | 3024 B |
| RAM | Dirty-line bitmap (168 bits), event queue, UI state, scratch | ~64 B |
| RAM | Stack | ~256 B, at the top of RAM |

The framebuffer takes three quarters of RAM, so **the game state lives in FRAM, not RAM**. FRAM writes as fast as
RAM and wears out only after about 10^15 writes, so the game can be updated in place. That also saves it
automatically: pull the batteries mid-game and it resumes where it was.

### FRAM write protection

`SYSCFG0.PFWP` protects program FRAM from stray writes. The game in `.persistent` sits in program FRAM, so
`store_open` clears PFWP before a state change and `store_close` sets it again straight after. Code and
constants are only writable for those few instructions. A version word and a checksum in the saved game let
`store_valid` reject a half-written or incompatible state (after a firmware update, say) and deal a new game.

## Display

### Driving it

From the LS013B7DH05 spec and `sharp.c`:

- **SPI**: UCB1 master, mode 0 (`UCCKPH`), LSB first (no `UCMSB`), 3-pin, SMCLK / 8 = 1 MHz.
- **SCS**: raise it, wait at least 6 µs (48 cycles at 8 MHz; `sharp.c` waits 64), send, wait for `UCBUSY` to
  clear, wait 2 µs, drop it, keep it low at least 6 µs before the next transfer.
- **Write lines**: mode byte `0x01` (M0, data update), then for each line its address (1–168, sent as is
  thanks to LSB-first), 18 data bytes (bit 0 of each byte is the leftmost pixel; 1 = white), one dummy byte;
  after the last line, one more dummy byte. Consecutive lines can go in one transfer, which is how dirty lines
  are flushed.
- **All clear**: `0x04`, `0x00`.
- **Power-up order**: SCS low, DISP low; clear the panel (all-clear) at least once; then DISP high and
  EXTCOMIN running (at least 30 µs apart, either order).
- **EXTCOMIN**: TB2 in up mode on ACLK, `TB2CCR0 = 272`, `TB2CCTL1 = OUTMOD_4` (toggle): 32768 / 273 / 2 = 60 Hz
  on P5.0, entirely in hardware.

A full screen is 168 × 20 bytes + 2, about 3.4 KB, 27 ms at 1 MHz; most moves change only a few dozen lines.

### Layout

144 × 168 pixels, portrait. Seven columns of 20 pixels (cards 19 wide with a 1-pixel gap) with 2-pixel margins:

```
y 0     +-----------------------------------------------+
        | [stock] [waste]    [ F1 ] [ F2 ] [ F3 ] [ F4 ]|   top row: cards 19 x 26
y 30    | [T1]  [T2]  [T3]  [T4]  [T5]  [T6]  [T7]       |   tableau, fanned downward
        |  ...                                          |
y 158   |                                               |
y 160   | status: moves, draw mode, selection hint      |   8-pixel text line
y 167   +-----------------------------------------------+
```

- A card face shows its rank and suit at the top left (5×7 rank glyphs A 2–10 J Q K, 5×7 suit symbols), which
  is all that's visible where cards overlap. The whole card shows only at the bottom of a column.
- Face-down cards fan by 3 pixels, face-up by 10, and the last card shows in full (26). The tableau has 128
  pixels (y 30–157). A column that doesn't fit squeezes in this order, each step only as far as needed:
  1. face-down strips from 3 pixels down to 1 (a stack of lines that still shows how many there are);
  2. face-up strips from 10 pixels down to 8 (the 7-pixel rank and suit glyphs plus the card's edge).
  The tallest legal column, 6 face-down + 13 face-up, then takes 6×1 + 12×8 + 26 = 128 pixels, an exact fit;
  normal spacing holds 9 face-up cards on 6 face-down (11 with none face-down), so most columns never squeeze.
  `ui.S` works out each column's strip sizes when it draws the column.
- Selection: the selected card (or run) is drawn inverted.
- Red suits (hearts, diamonds) can't be coloured, so they're drawn as outlined symbols and black suits
  (spades, clubs) as solid ones.

### Redrawing

`gfx` draws into the framebuffer and marks the lines it touched in the dirty-line bitmap; `lcd_flush` sends
all the dirty lines in one transfer (each line carries its own address, so they needn't be next to each other)
and clears their bits. After a move `ui_draw` redraws only the piles the move changed
(each pile has a known rectangle), plus the status line.

## Buttons and controls

### Handling

- Ports 1–3: the button pins as inputs with pull-ups (`PxREN`, `PxOUT` = 1), interrupt on the falling edge
  (`PxIES` = 1), so pressing a button wakes the chip.
- On an interrupt, read `PxIV` (which clears the flag), queue the button, disable that pin's interrupt and
  give it a 30 ms lockout. TB0 (ACLK ÷ 64, 512 Hz, continuous; see Watchdog) with its CCR0 compare set for the
  next lockout to end (about 15 counts),
  re-enables pins whose lockout ended and whose pin reads high again (released). That rejects both press and
  release bounce without polling.
- Only presses are events. Holding a button does nothing more (no auto-repeat).
- Events carry a button's role (tableau 3, stock, undo...), not its pin. One table in `buttons.S` maps each
  pin to a role, so when buttons move on the board (likely, once the screen layout is settled) only that table
  and `hw/sol` change; the game and interface code don't.

### Controls (proposal)

| Button | Meaning |
| --- | --- |
| Stacks 1–7 | Tableau columns 1–7, left to right |
| Stack 8 | Waste |
| Stack 9 | Stock: deal to the waste (or turn the waste over when the stock is empty) |
| Suits 1–4 | Foundations 1–4 |
| SW1 | New game (press twice to confirm) |
| SW2 | Undo |
| SW3 | Options: the rules and extras (see Options below) |

Moving cards is two presses, source then destination:

- **Source**: a tableau column, the waste, or a foundation. Its top card is shown selected.
- **Destination**: a tableau column or a foundation. Between tableau columns, the run that fits is moved: the one
  whose bottom card is one lower and the opposite colour of the destination's top card, or the run starting
  with a king for an empty column. There's no buzzer, so an illegal destination flashes the status line and
  keeps the selection.
- **Same button twice**: sends the source's top card to its foundation if it can go, else cancels the selection.
- Uncovered face-down cards turn over automatically.

### Options

SW3 opens an options screen in place of the game; SW3 again closes it and returns to the game as it was.
On the options screen each setting sits beside a button, which steps through its values:

| Setting | Values | Default |
| --- | --- | --- |
| Draw | 1 card, 3 cards | 3 |
| Stock passes | Unlimited, 3, 1 | Unlimited |
| Scoring | Off (move count only), Standard, Vegas | Off |
| Statistics | Shown on the screen: games played and won, win rate, current and best streak; one button resets them | |

Settings are kept in `.persistent` with the game. A change to Draw, Stock passes or Scoring applies from the
next new game, so a game in progress keeps the rules it started with (they're saved with it).

## Game

### Data

A card is one byte: bits 0–3 rank (1–13), bits 4–5 suit (0 spades, 1 clubs, 2 hearts, 3 diamonds, so bit 5 set
means red), bit 7 face up.

Thirteen piles, each a count byte and a fixed-size array, in `.persistent`:

| Pile | Most cards | Bytes |
| --- | --- | --- |
| Stock | 24 | 25 |
| Waste | 24 | 25 |
| Foundations × 4 | 13 | 4 × 14 |
| Tableau × 7 | 19 (6 face down + 13 face up) | 7 × 20 |

About 250 bytes in all. Moves only append to or remove from the end of an array, so no linked lists are needed.

### Moves and undo

A move is recorded in four bytes: source pile, destination pile, card count, and flags ("turned a card face up",
"turned the waste over", "draw 3"). Applying a move and undoing it are exact inverses using the record, so undo
needs no snapshot. The log is a ring of 256 moves (1 KB) in `.persistent`. That allows undo back 256 moves,
across power loss too.

### Dealing and shuffling

- `rng`: xorshift32. Small, fast in assembly (shifts and XORs on two words), good enough for shuffling.
- Seed: the TB0 count at the moment of the first button press after power-up (people's timing is random at
  ACLK resolution), mixed with a counter in `.persistent` that increases with every deal. The seed is saved with
  the game, so a deal can be replayed.
- Fisher–Yates shuffle of the 52 cards, then the standard Klondike deal: column *n* gets *n* cards, the last
  face up; the remaining 24 go to the stock face down.
- A test build can fix the seed (`-DTEST_SEED=0x1234`, possible because `.S` files go through cpp) to make
  deals repeatable.

### Rules

Standard Klondike: tableau builds down in alternating colours, an empty column takes only a king or a run
starting with one; foundations build up by suit from the ace; stock deals one card (or three) to the waste, and
turns over without limit (an option could limit passes). A game is won when all four foundations hold 13 cards.
That gets a win screen, and the win is added to the statistics.

## Testing

1. **In NetBeans**: Run and Debug on the Solitaire board for interactive work; breakpoints in the `.S` files;
   Variables shows peripheral registers by name; Watches for the game state (for example
   `*(unsigned char (*)[25])&stock`).
2. **Automated**, in `sw/sol/tests/`: a script builds the firmware with a fixed seed and runs scenarios on
   `msp430_run`, with the display connected:
   - deal with seed *s* → screen matches `deal_s.pbm`;
   - press sequences (`--pin N=0@t --pin N=z@t'`) for legal and illegal moves → piles (read with `--peek` at
     addresses from `msp430-elf-nm`) and screen match;
   - undo returns the exact earlier state;
   - EXTCOMIN 60 Hz and no display timing problems (the runner's `--sharp` report);
   - the chip is in LPM3 between presses (the runner can sample the SR, or count cycles run).
   Approved pictures are checked in; a mismatch shows the new picture to inspect.
3. **On hardware**: power-up, display, every button, sleep current (a µA meter in series with the batteries),
   then a long soak.

## Milestones

Each step ends with something visible in the simulator and, from step 2, an automated test.

1. **Skeleton**: the module files, `sys_init` (watchdog held during set-up, 8 MHz, REFO LP for ACLK, TB0 time
   base, unused pins low, LOCKLPM5 cleared, watchdog started on ACLK), the sleep loop with its kick. Check: MCLK
   8 MHz, the CPU asleep in LPM3, no reset over 10 simulated minutes of idle, and a deliberate hang (a test build
   with an endless loop) reset within 256 s with `SYSRSTIV` 0x16.
2. **Display** (details in `STEP2-display.md`): SPI, all-clear, EXTCOMIN on TB2.1, DISP, framebuffer,
   `lcd_flush` with dirty lines; a test pattern. Check: the display's status line shows 60 Hz and no timing problems; the picture matches.
3. **Graphics** (details in `STEP3-graphics.md`): font and suit glyphs, card faces, backs, empty slots, inverted selection, text. Check: a sheet
   of all 52 cards.
4. **Buttons**: interrupts, debounce, event queue; a test screen that marks each button pressed (like
   `buttons.c`). Check: scripted presses, including bouncing ones, give exactly one event each.
5. **Game model**: cards, piles in `.persistent`, rng, shuffle, deal, the draw of the opening layout. Check:
   seeded deals match expected layouts.
6. **Moves**: rules, multi-card moves, stock and waste, automatic turn-over, win detection. Check: scripted games,
   including a full winning game from a known seed.
7. **Interface**: two-press moves, selection display, same-button-twice to foundation, status line, layout
   compression of long columns, win screen.
8. **Undo, new game, options**: the undo log, confirm for new game, the options screen (draw 1/3, stock
   passes, scoring, statistics).
9. **Saving**: FRAM write protection discipline, version and checksum, resume after power-up (in the simulator:
   reset mid-game and check the game is back).
10. **Power**: confirm LPM3 everywhere, nothing left running; measure on hardware when boards exist.
11. **Hardware bring-up**: programming over Spy-Bi-Wire, the display's power-up order on real glass, button feel,
    current.

## Open decisions

- **Button mapping**: the table above is provisional; buttons will move to suit the screen layout once it's
  designed.

## References

- MSP430FR2355 datasheet and the MSP430FR4xx/FR2xx family user's guide (SLAU445): in NetBeans under **Help >
  MSP430 Documentation**; the datasheet is also in `docs/datasheets/`.
- Sharp LS013B7DH05 spec: `docs/datasheets/LS013B7DH05_spec.pdf` (text in `ls013dh05.txt`).
- The board: `hw/README.md`, `hw/sol/sol.kicad_sch`.
- The simulator and its tests: `sim/picsimlab-msp430/MSP430.md`; working C examples of the display and buttons
  in its `src/sim_backend/msp430/tests/` (`sharp.c`, `buttons.c`).
- The MSP430 Assembly plugin's README (projects, building, debugging): `~/NetBeansProjects/msp430-asm/README.md`.
