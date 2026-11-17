# Step 11: hardware bring-up

From the plan (`PLAN.md`, Milestones):

> **Hardware bring-up**: programming over Spy-Bi-Wire, the display's power-up order on real glass, button feel,
> current.

The firmware is finished and tested in the simulator. This step takes it onto the boards from JLCPCB
(`hw/ORDERING.md`), one check at a time, so a problem shows up on its own.

**Status: waiting for the boards and displays.**

## What you need

- A board, a display, a 2 × AA holder with cells.
- A programmer: an MSP430 LaunchPad's eZ-FET (its 3V3/TST/RST/GND jumpers off, four wires across to J3's holes),
  or an MSP-FET. Software: `mspdebug` (`mspdebug tilib` or `mspdebug ezfet`), or TI's UniFlash.
- A bench supply with a current limit, a multimeter, and ideally a scope.
- For J3 (left off for the case): a 4-pin header pressed into its holes from the back, or pogo pins.

## 1. Power, without the display

1. Look over the board: the parts' rotations (U1, U2, Q1: pin 1), solder bridges on U1's and DS1's fine pins.
2. From the bench supply at 3.0 V, current limited to 20 mA, into the battery pads. Expect a few hundred µA (the MCU
   unprogrammed, running from reset).
3. Measure the rail at J3's 3V0: 3.0 V. Raise the supply from 1.8 to 3.4 V: the rail should hold 3.0 V
   throughout (the TPS63900 bucks and boosts).
4. **Reverse the supply** (it should draw nothing: Q1 blocks it), then put it back.

## 2. Programming

1. Connect the programmer to J3: 3V0, TST, RST, GND. Power the board from its own supply, not the programmer's.
2. `mspdebug tilib "prog sw/sol/build/sol.hex"` (or NetBeans' Run once it can reach the board).
3. Read it back (`mspdebug ... "verify sw/sol/build/sol.hex"`).

If the programmer can't find the chip: check RST/SBWTDIO has its 47 kΩ pull-up and at most 1 nF, and that TEST
isn't held.

## 3. The display

1. Power off. Fit the display (`hw/ORDERING.md`, *Fitting the display*). **Measure how far the ribbon went in**: the
   case window assumes the glass's bottom edge 11.0 mm above the connector's pad row, ±0.5 mm.
2. Power on: the title screen (or a game) should appear within a second.
3. With a scope: EXTCOMIN (P5.0) at 60 Hz; DISP (P5.1) high; SCS idle low. The display's power-up order (cleared
   before DISP high) is in `lcd`; on real glass, a wrong order shows as a brief flash of noise.
4. Look for lines that don't update (a bad SPI bit or a timing problem: try a slower `UCB1BRW`).

## 4. Buttons

1. Press each button once and check each is counted under the right role, on step 4's button test screen:
   `tests/run.sh` builds it as `tests/out/buttons.hex` (`-DTEST_SCREEN=3`); program that.
2. **Bounce**: press quickly and slowly; every press must count exactly once. The debounce needs a release seen on
   two ticks 29 ms apart; real switches may need more (raise the tick in `tick_start`) or less.
3. **Feel**: with the case's caps on, every button must click without binding (`hw/case/README.md`).

## 5. The game, then the case

1. Program the game. Deal, play, undo, the options; pull the batteries mid-game and put them back: the game
   should come back.
2. Fit the board in the case and check the window over the display, the caps, and the battery leads' notch.

## 6. Current (STEP10-power.md, section 4)

Sleep current with the game on screen; per-press current on a scope; then a **soak**: a day or more running with
occasional play, checking it never hangs (the options screen shows watchdog resets if it ever did).

## Record what you find

Note each measurement and anything that needed changing in this file, as the earlier steps did: the sleep current,
the ribbon depth, debounce changes, and any board fixes for a second revision (`hw/README.md`, Open items).
