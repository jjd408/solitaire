# Step 10: power

From the plan (`PLAN.md`, Milestones):

> **Power**: confirm LPM3 everywhere, nothing left running; measure on hardware when boards exist.

**Status: the firmware side is done** (checked in the simulator); the measurements wait for the boards (step 11).

## 1. Where the power goes

| State | Time | Current (datasheet and estimates) |
| --- | --- | --- |
| Asleep in LPM3: CPU, MCLK and SMCLK off; ACLK (REFO, low-power) running TB2 for EXTCOMIN and TB0 for the watchdog | Nearly all of it | About 1 µA (LPM3) + 1 µA (REFO LP) + the display's static current (a few µA for this family) + 75 nA (the regulator) |
| Awake for a press: the move, drawing, and sending the changed lines | About 11 ms a press on average (92,000 cycles) | About 1 mA at 8 MHz |
| Awake for the watchdog: TB0 wraps every 128 s and wakes `main` to kick it | A few hundred cycles | Negligible |

So a day of 1000 presses costs about 11 s awake, about 3 µAh; sleeping costs about 24–100 µAh a day, depending on
the display. Two AA cells (about 2000 mAh) last years either way: sleep dominates, and the code's speed hardly
matters.

## 2. What the firmware does about it

- **Sleeps in LPM3** with interrupts on (`bis #LPM3_bits|GIE, SR`), only when the event queue is empty, checked with
  interrupts off so no press is missed.
- **Stops the debounce tick** (TB0 CCR0) as soon as no button is locked.
- **Sends only the lines that changed**, and redraws a column only as far down as it went (`STEP7-interface.md`),
  as the CPU waits on SPI while sending.
- **Unused pins are driven low**, so none float (`system`).
- **No LPM3.5/LPM4.5**: they'd stop EXTCOMIN, which the display needs while it's on (PLAN.md, Clocks and power).

## 3. Checked in the simulator

| Test | Checks | Result now |
| --- | --- | --- |
| `step10_idle` | After a deal, 5 minutes of no presses may cost at most 5000 cycles awake (the TB0 wake-ups), and the CPU ends in LPM3 | 566 cycles |
| `step10_press` | 40 presses of real play average at most 150,000 cycles each (19 ms) | About 92,000 |
| `step4_buttons counts` | Asleep in LPM3 after a burst of presses | |

## 4. On the boards (with step 11)

1. **The sleep current**: a µA meter (or a µCurrent-style shunt amplifier) in series with the batteries, the game
   on screen, no presses. Expect a few µA; much more means something is running (look at SMCLK, a timer, or a
   floating pin).
2. **A press**: a scope across a 10 Ω shunt, to see the awake time and current per press.
3. **The display's share**: compare the sleep current with the display's ribbon in and out.
4. **The regulator**: its quiescent current is tiny, but check its efficiency at the sleep current (TPS63900's
   datasheet: high even at µA loads).

If the sleep current is higher than expected, the first suspects are REFO in high-power mode (15 µA), the debounce
tick left running, or a button pin without its pull-up.
