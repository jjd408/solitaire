# Step 2: the display

From the plan (`PLAN.md`, Milestones):

> **Display**: SPI, all-clear, EXTCOMIN on TB2.1, DISP, framebuffer, `lcd_flush` with dirty lines; a test
> pattern. Check: the display's status line shows 60 Hz and no timing problems; the picture matches.

The goal is the Sharp LS013B7DH05 showing a test picture, with EXTCOMIN running and every timing within the spec.
The simulator's `sharp.c` (`sim/picsimlab-msp430/src/sim_backend/msp430/tests/`) does all of this in C on the
same pins; compare with it at each stage.

## 1. Pins (in `system`, before `LOCKLPM5`)

Pins have to be set up before the lock is released, so these go in `system`'s port section, not in `lcd.S`.

| Pin | Set-up |
| --- | --- |
| P4.5 SCLK, P4.6 SI | `P4SEL0` bits 5 and 6 = 1: handed to UCB1 (SPI) |
| P4.7 SCS | Output, low |
| P5.0 EXTCOMIN | `P5SEL0` bit 0 = 1 (TB2.1 output) and `P5DIR` bit 0 = 1 |
| P5.1 DISP | Output, low: the display stays off until it's been cleared |

## 2. Peripherals (`lcd_init` in `lcd.S`)

SPI on UCB1: mode 0, LSB first, master, 1 MHz from SMCLK.

```asm
        mov.w   #UCSWRST, &UCB1CTLW0                     ; hold it in reset while configuring
        bis.w   #UCCKPH|UCMST|UCSYNC|UCSSEL__SMCLK, &UCB1CTLW0 ; no UCMSB: LSB first
        mov.w   #8, &UCB1BRW                             ; 7.995 MHz / 8 = 999 kHz (limit 1.1 MHz)
        bic.w   #UCSWRST, &UCB1CTLW0                     ; run
```

EXTCOMIN from TB2: 60 Hz in hardware, with no interrupts and no CPU time.

```asm
        mov.w   #272, &TB2CCR0                           ; up mode: 273 counts = 120 Hz at ACLK
        mov.w   #100, &TB2CCR1                           ; any value below CCR0
        mov.w   #OUTMOD_4, &TB2CCTL1                     ; toggle: TB2.1 = 60 Hz on P5.0
        mov.w   #TBSSEL__ACLK|MC__UP|TBCLR, &TB2CTL
```

Power-up order (Sharp's spec, section 6-2): clear the panel with SCS and DISP low, then raise DISP. EXTCOMIN
and DISP must start at least 30 µs apart, in either order; starting TB2 before the clear leaves far more than
that.

## 3. Sending bytes (`lcd.S`)

| Routine | Does |
| --- | --- |
| `spi_byte` (R12) | Waits for `UCTXIFG` in `UCB1IFG`, then `mov.b R12, &UCB1TXBUF` |
| `lcd_select` | SCS high (`bis.b #BIT7, &P4OUT`), then waits at least 6 µs (tsSCS) |
| `lcd_deselect` | Waits until `UCBUSY` in `UCB1STATW` clears (the last bit is out), waits at least 2 µs (thSCS), SCS low, then waits at least 6 µs before the next transfer can start |
| `lcd_clear` | Select, send `0x04` (all clear) and `0x00`, deselect |

Delays at 7.995 MHz: a `dec.w R15` / `jnz` loop takes 3 cycles per pass. 6 µs is 48 cycles; allow a margin with
22 passes (66 cycles, about 8 µs). 2 µs: 8 passes (3 µs).

## 4. Framebuffer and dirty lines

In `.bss`:

```asm
fb:     .skip   168*18          ; 3024 bytes: 168 lines of 144 pixels, one bit each
dirty:  .skip   22              ; one bit per line (168 bits = 21 bytes; 22 keeps it even)
```

- Bit 0 of each byte is the leftmost pixel, because bytes go out LSB first. **1 = white.**
- gcc's start-up code zeroes `.bss`, which would be an all-black screen, so `lcd_init` fills `fb` with 0xFF (a
  loop of 1512 word writes).
- Drawing code sets a line's bit in `dirty` whenever it changes the line.

## 5. `lcd_flush`

Every dirty line goes in one transfer; then their bits are cleared.

```
if no bit in dirty is set: return
select
send 0x01                         ; M0: data update
for each line y (0-167) whose dirty bit is set:
    send y + 1                    ; line address, 1-168 (LSB first, so sent as is)
    send fb[y*18] ... fb[y*18+17] ; 18 bytes of pixels
    send 0x00                     ; dummy
    clear its dirty bit
send 0x00                         ; the closing dummy
deselect
```

Each line carries its own address, so the dirty lines don't need to be next to each other: any set of lines
goes in one transfer. A full screen takes about 27 ms.

## 6. A test pattern

Something that shows the pixel order is right:

- a 1-pixel black border around the edge;
- a few card-sized outlines;
- a checkerboard of 8 × 8 squares;
- a diagonal line, which makes a wrong bit order obvious at once.

Then mark all 168 lines dirty, call `lcd_flush`, and sleep. Only simple loops are needed; real drawing routines
are step 3.

`main` becomes: `system`, `lcd_init`, draw the test pattern, `lcd_flush`, then the same sleep loop as now.

## 7. Checking it

- **Automatically**, with the simulator's display model (SCLK, SI, SCS, EXTCOMIN and DISP by package pin):

  ```sh
  msp430_run build/sol.hex --seconds 2 --tick 8e6 --sharp 18,17,16,37,36,screen.pbm
  ```

  It reports something like `sharp: 2 frames, 168 lines written, EXTCOMIN 60 Hz, DISP 1, ... no timing
  problems` and saves the screen as `screen.pbm` to look at. If SCS is raised too soon, the clock is too fast or
  EXTCOMIN is off frequency, it says so instead. `--tick 8e6` makes the simulator's time steps fine enough for a
  1 MHz SPI clock. The runner is in `sim/picsimlab-msp430/src/sim_backend/msp430/tests/`.
- **In NetBeans**: Run shows it on PICSimLab's Solitaire board, with the display's status line under the picture
  (green when it's happy; red, with the first problem, when it isn't). Debug lets you break in `lcd_flush` and
  watch the UCB1, TB2, P4 and P5 registers in Variables.

Once the picture is right and the status line is clean, `screen.pbm` becomes the approved picture for the first
automated test in `sw/sol/tests`, as the plan describes.

## Watch out for

- UCB1 ignores most of its settings unless they're written while `UCSWRST` is set.
- `UCTXIFG` only means the transmit buffer is free. Wait for `UCBUSY` to clear before dropping SCS, or the last
  bits are cut off.
- `.bss` starts black: fill the framebuffer before the first flush.
- Raise DISP only after the clear, or random pixels flash up at power-on on real glass.
