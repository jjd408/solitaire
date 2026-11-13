# Step 4: buttons

From the plan (`PLAN.md`, Milestones):

> **Buttons**: interrupts, debounce, event queue; a test screen that marks each button pressed (like
> `buttons.c`). Check: scripted presses, including bouncing ones, give exactly one event each.

The goal: each press of any of the 16 buttons wakes the chip and puts exactly one event in a queue, however much
the switch bounces, and `main` takes events from the queue one at a time. No polling: the chip stays in LPM3
until a button changes.

## 1. The buttons

All switch to ground, so a button reads 0 while it's held. Package pins are what the simulator's `--pin` uses.

| Button | Pin | Package pin | Role (the event it gives) |
| --- | --- | --- | --- |
| Stacks 1–4 | P1.0–P1.3 | 7, 6, 5, 4 | `B_TABLEAU1`–`B_TABLEAU4` (1–4) |
| Stacks 5–7 | P1.4–P1.6 | 31, 30, 29 | `B_TABLEAU5`–`B_TABLEAU7` (5–7) |
| Stack 8 | P2.0 | 27 | `B_WASTE` (8) |
| Stack 9 | P2.1 | 26 | `B_STOCK` (9) |
| Suits 1–4 | P2.2–P2.5 | 25, 24, 15, 14 | `B_FOUND1`–`B_FOUND4` (10–13) |
| SW1 | P3.0 | 3 | `B_NEW` (14) |
| SW2 | P3.1 | 2 | `B_UNDO` (15) |
| SW3 | P3.2 | 1 | `B_OPTIONS` (16) |

Events are **roles**, not pins (the plan's rule): one table in `buttons.S`, a byte per port bit, maps each pin
to its role, so when buttons move on the board only that table changes. 0 means "no button" (an empty queue, or
an unused pin).

### The roles

What each button means to the game (`PLAN.md`, Controls), and the number its events carry. They go in `sol.h`:

```c
/* Button roles: what an event means, whichever pin it came from (buttons.S maps pins to roles) */
#define B_NONE      0           /* no event: the queue is empty */
#define B_TABLEAU1  1           /* tableau columns 1-7, left to right: B_TABLEAU1 + n - 1 for column n */
#define B_TABLEAU2  2
#define B_TABLEAU3  3
#define B_TABLEAU4  4
#define B_TABLEAU5  5
#define B_TABLEAU6  6
#define B_TABLEAU7  7
#define B_WASTE     8           /* the waste pile: a source for a move */
#define B_STOCK     9           /* deal to the waste, or turn the waste over when the stock is empty */
#define B_FOUND1    10          /* foundations 1-4: B_FOUND1 + n - 1 for foundation n */
#define B_FOUND2    11
#define B_FOUND3    12
#define B_FOUND4    13
#define B_NEW       14          /* new game (press twice to confirm) */
#define B_UNDO      15          /* undo the last move */
#define B_OPTIONS   16          /* open or close the options screen */
#define B_ROLES     17          /* how many role numbers there are, counting B_NONE: sizes tables by role */
```

| Role | Value | Button now | Meaning |
| --- | --- | --- | --- |
| `B_NONE` | 0 | — | No event |
| `B_TABLEAU1`–`B_TABLEAU7` | 1–7 | Stacks 1–7 | Tableau column 1–7: a source or destination |
| `B_WASTE` | 8 | Stack 8 | The waste: a source |
| `B_STOCK` | 9 | Stack 9 | Deal to the waste, or turn it over |
| `B_FOUND1`–`B_FOUND4` | 10–13 | Suits 1–4 | Foundation 1–4: a source or destination |
| `B_NEW` | 14 | SW1 | New game, confirmed by a second press |
| `B_UNDO` | 15 | SW2 | Undo |
| `B_OPTIONS` | 16 | SW3 | Options screen, open or close |

The numbers are chosen so the game can compute with them: a tableau role minus `B_TABLEAU1` is the column
number (0–6), a foundation role minus `B_FOUND1` the foundation (0–3), and a role tests as a pile with
`cmp.b #B_FOUND4+1` (1–13 are piles, 14–16 commands). `B_ROLES` sizes anything indexed by role, such as the
test screen's `presses` counts.

## 2. Pins (in `system`, before `LOCKLPM5`)

Like the display pins, they're set while the lock is on. The masks are P1 `0x7F`, P2 `0x3F`, P3 `0x07`.

| Register | Setting | Why |
| --- | --- | --- |
| `PxDIR` | bits clear | Inputs |
| `PxREN` | bits set | Resistor on |
| `PxOUT` | bits set | ...as a pull-up (with REN set, OUT picks up or down) |
| `PxIES` | bits set | Interrupt on the falling edge: the press |

Set OUT before REN, so a pin never pulls down for a moment.

## 3. `btn_init` (in `buttons.S`, called after `system`)

1. Clear `P1IFG`, `P2IFG`, `P3IFG`: releasing `LOCKLPM5` can set flags, and a stale flag would be a press
   nobody made.
2. Set `P1IE`, `P2IE`, `P3IE` for the button bits.
3. Empty the queue (head = tail = 0; `.bss` is zero anyway, but say so).

Interrupts start when `main` first sleeps with GIE set.

## 4. The port interrupts: a press

One routine per port (vectors `__interrupt_vector_port1`, `_port2`, `_port3`). Each:

1. **Saves every register it uses.** An interrupt can arrive in the middle of any code, including code that's
   relying on R12–R15, so the usual "R11–R15 may change" doesn't apply: push and pop all of them. (Only SR and
   PC are saved by the interrupt itself.)
2. Reads `PxIV`. That returns the highest-priority pending pin as 2 × (bit + 1), and clears that pin's flag.
   0 means nothing more is pending. Loop until it reads 0, handling each pin:
   - bit = `PxIV` / 2 − 1;
   - **clear that pin's `PxIE` bit**: its bounces now can't interrupt;
   - set its bit in the port's `locked` byte;
   - look up its role and add it to the queue;
   - start the debounce timer if it isn't running (section 5).
3. Wakes `main`: `bic.w #LPM3_bits, n(SP)`, where n is the number of bytes pushed in step 1, because SR is
   on the stack under them.
4. Pops what it pushed, `reti`.

## 5. Debounce: the TB0 CCR0 interrupt

TB0 already runs at 512 Hz (ACLK / 64) in continuous mode for the watchdog wake-up; its overflow uses vector 42
(`TB0IV`). CCR0 has its own vector, 43 (`TIMER0_B0`), free for this. 15 counts = 29.3 ms.

**Starting it** (from a port interrupt, when no button was locked): `TB0CCR0` = now + 15, then set `CCIE` in
`TB0CCTL0`. TB0 counts on ACLK while the CPU runs on MCLK, so read `TB0R` twice and use the value when two reads
agree (TI's advice for reading a timer clocked asynchronously).

**Each tick** (vector 43; the flag clears itself on this vector), for each locked pin:

| The pin reads | Its `seen_up` bit | Then |
| --- | --- | --- |
| 0 (still held) | | Clear `seen_up` |
| 1 (released) | clear | Set `seen_up` |
| 1 | set | **Unlock it**: clear its `PxIFG`, set its `PxIE`, clear `locked` and `seen_up` |

Then, if any pin is still locked, `TB0CCR0` += 15 for the next tick; otherwise clear `CCIE`.

**Why two ticks released:** bounce comes at both ends of a press. Locking the pin at the first falling edge
hides the press bounces. A pin that reads released once might be in the middle of its release bounce; two reads
30 ms apart, both released, means it has settled. A button is ready again 30–60 ms after it's let go, quicker
than anyone presses twice.

**Holding a button** gives one event, however long: it stays locked (ticking every 30 ms) until it's released.
No auto-repeat, as the plan says.

`locked` and `seen_up` are a byte each per port, in `.bss`.

## 6. The event queue

A ring of 16 bytes in RAM (`events` in `main.S` is already there; move it to `buttons.S`), with a head byte
(next to take) and a tail byte (next free):

- **Put** (in a port interrupt): if (tail + 1) & 15 == head the queue is full: drop the event. Else write
  `events[tail]`, then tail = (tail + 1) & 15.
- **`btn_next`** (from `main`): if head == tail return R12 = 0; else R12 = `events[head]`, head = (head + 1) & 15.

Only interrupts write the tail and only `main` writes the head, so neither needs interrupts off, as long as each
writes the data before moving its index. 16 entries is far more than anyone can press ahead of the game.

## 7. `main`'s loop

The plan's event loop, now with real events. Interrupts go off while checking the queue, so a press can't slip
in between "the queue is empty" and going to sleep (it would sit there until the next press):

```asm
loop:   mov.w   #WDT_RUN, &WDTCTL       ; kick the watchdog
        call    #lcd_flush
        dint                            ; no interrupts while deciding to sleep
        nop
        call    #btn_pending            ; R12 = 1 if the queue has something (doesn't enable interrupts)
        tst.w   R12
        jnz     1f
        bis.w   #LPM3_bits|GIE, SR      ; sleep, and enable interrupts, in one instruction
        nop
1:      eint
        call    #btn_next               ; R12 = the role, or 0
        tst.w   R12
        jz      loop
        ; ... handle the event ...
        jmp     loop
```

`bis.w #LPM3_bits|GIE, SR` both enables interrupts and sleeps, so an interrupt that was waiting runs only after
the chip is asleep, and wakes it. (TI asks for a `nop` after `dint` and around changes to GIE.)

## 8. The test screen (`TEST_SCREEN` 3)

Like `buttons.c`, but counting events, not showing levels: one box per button, laid out as on the board (row 1
SW1–SW3, row 2 stacks 1–9, row 3 suits 1–4), each with its press count under it, drawn with step 3's `gfx`. For
each event, `main` adds one to that role's count (a byte array `presses`, by role) and redraws the box and its
number: an event's box is drawn inverted until the next event, so the last button pressed shows.

New file `testbuttons.S`: `button_screen` draws it all, `button_event` (R12 = role) counts and redraws.

## 9. Checking it

A new line in `tests/run.sh` (`build buttons -DTEST_SCREEN=3`), with `--pin` presses. `N=0@t` holds pin N low
from time t; `N=z@t` lets it go, back to the pull-up. A script of, for example:

| Press | Pins | Checks |
| --- | --- | --- |
| Clean | each of the 16 once, 100 ms each, 200 ms apart | Every count is 1 |
| Press bounce | `0`, `z`, `0`, `z`, `0` 0.5 ms apart, then held | Counts 1, not 3 |
| Release bounce | held, then `z`, `0`, `z`, `0`, `z` 0.5 ms apart | Counts 1 (no second press) |
| Long hold | held 2 s | Counts 1 (no repeat) |
| Two at once | two buttons pressed 1 ms apart | Each counts 1 |
| Quick second press | released, pressed again 200 ms later | Counts 2 |

Checks: the screen against an approved picture (`step4_buttons.pbm`); the counts, read with
`--peek ADDR:WORDS` at `presses` (its address from `msp430-elf-nm out/buttons.elf`); and that the chip ended
asleep (the runner's final SR has the LPM3 bits, `0x00D8`, set). `run.sh` will need a small helper for the
`--peek` check.

In NetBeans, Run on the Solitaire board and click the buttons; Debug can break in `port1_isr` or watch
`presses`.

## Watch out for

- **Every register an interrupt uses must be pushed**, R11–R15 too.
- **The `bic.w #LPM3_bits, n(SP)` offset** counts what the routine pushed: with 4 registers pushed, SR is at
  8(SP).
- **Read `PxIV` once per pin**: each read clears a flag. Keep the value in a register.
- **`PxIV` / 2 − 1 is the bit number**; the role table is indexed by it.
- **Clear `PxIFG` before setting `PxIE`** when unlocking, or the bounces that happened while it was locked
  fire straight away.
- **`TB0CCR0` arithmetic wraps** at 65536, which is what's wanted: the comparison is for equality.
- **CCR0's flag clears itself** when its vector is taken; the TB0 overflow (vector 42) still needs its `TB0IV`
  read.
- The simulator's switches don't bounce unless the script makes them; the hardware's will, so the bounce cases
  in the test matter.
