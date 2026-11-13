# Step 1: the skeleton

From the plan (`PLAN.md`, Milestones):

> **Skeleton**: the module files, `sys_init` (watchdog held during set-up, 8 MHz, REFO LP for ACLK, TB0 time
> base, unused pins low, LOCKLPM5 cleared, watchdog started on ACLK), the sleep loop with its kick. Check: MCLK
> 8 MHz, the CPU asleep in LPM3, no reset over 10 simulated minutes of idle, and a deliberate hang (a test build
> with an endless loop) reset within 256 s with `SYSRSTIV` 0x16.

The goal: a program that starts the chip the way every later step needs it (clocks, timers, pins, the watchdog)
and then sleeps, waking only when an interrupt asks it to. This doc was written after the step, as a record of
what was built and how it was checked; the later steps added to the same files.

## 1. The files

One file per module (the plan's Modules table), each starting from the plugin's `.S` template with its
`#include <msp430.h>` and an empty routine. Step 1 filled in two of them:

| File | Step 1's part |
| --- | --- |
| `system.S` | `system` (the plan's `sys_init`): everything set up at power-on; `tb0_wrap_isr` |
| `main.S` | `main`: calls `system`, then the sleep loop |
| `sol.h` | Constants shared by the files: `WDT_RUN`, `TB0_SETUP` |

The others (`lcd.S`, `gfx.S`, `font.S`, `buttons.S`, `game.S`, `ui.S`, `store.S`) stayed empty until their
steps. gcc's start-up code (`__crt0_start`) runs before `main`: it sets the stack pointer to the top of RAM
(0x3000), zeroes `.bss`, copies `.data`'s starting values, then calls `main`.

## 2. `system`, in order

The order matters: the watchdog first, pins before the lock is released, the watchdog last.

**1. Stop the watchdog.**
```asm
        mov.w   #WDTPW|WDTHOLD, &WDTCTL
```
It runs from reset on SMCLK at 1 MHz with a 32 ms time-out, too short for set-up. Every write to `WDTCTL` must
include the password `WDTPW` (0x5A00); a write without it resets the chip at once.

**2. Unused pins: outputs, driven low.** An unconnected input floats and can draw current; a low output is the
lowest-current state. `PxOUT` is cleared before `PxDIR` is set, so no pin drives high even for an instant
(`PxOUT` isn't defined after reset).

| Pins | Why unused |
| --- | --- |
| P1.7 | Spare |
| P2.6, P2.7 | XOUT/XIN: no crystal |
| P3.3–P3.7 | Spare |
| P4.0–P4.4 | Spare (P4.4 is UCB1STE, not used: SCS is P4.7) |
| P5.2–P5.4, P6.0–P6.6 | Not on the TSSOP-38 package, but present inside the chip |

(Steps 2 and 4 later added the display's and the buttons' pins here.)

**3. Release the pin lock.**
```asm
        bic.w   #LOCKLPM5, &PM5CTL0
```
After power-on the FR2355 holds every pin in a high-impedance state until `LOCKLPM5` is cleared, so settings
written to the port registers don't reach the pins until then. Set the pins up first, then release the lock.

**4. Clocks: MCLK and SMCLK at 8 MHz from the DCO, locked by the FLL to REFO; ACLK from REFO.**
```asm
        bis.w   #SCG0, SR                               ; FLL off while changing it
        nop
        mov.w   #SELREF__REFOCLK|REFOLP, &CSCTL3        ; FLL reference REFO, in its low-power mode
        mov.w   #DCORSEL_3, &CSCTL1                     ; DCO range up to 8 MHz
        mov.w   #FLLD_0|243, &CSCTL2                    ; DCOCLKDIV = (243 + 1) x 32768 = 7,995,392 Hz
        nop
        nop
        nop
        bic.w   #SCG0, SR                               ; FLL on
1:      bit.w   #FLLUNLOCK0|FLLUNLOCK1, &CSCTL7         ; wait until it locks
        jnz     1b
        mov.w   #SELMS__DCOCLKDIV|SELA__REFOCLK, &CSCTL4 ; MCLK = SMCLK = DCOCLKDIV, ACLK = REFO
```
- `CSCTL2`: FLLN = 243 multiplies the 32,768 Hz reference by N + 1 = 244; FLLD_0 divides by 1. 8 MHz needs no
  FRAM wait states (above 8 MHz it would), so `FRCTL0` isn't touched.
- The FLL is turned off (`SCG0`) while its settings change, and the three `nop`s give it time before it's turned
  back on, as TI's examples do.
- REFO in low-power mode (`REFOLP`) draws about 1 µA and stays within ±3.5%, enough to keep EXTCOMIN inside
  57–66 Hz. There's no crystal; VLO would be too inaccurate.

**5. TB0: a slow time base on ACLK.**
```asm
        mov.w   #TBIDEX__8, &TB0EX0                     ; ACLK / 8 ...
        mov.w   #TB0_SETUP, &TB0CTL                     ; ... / 8 again = 512 Hz, continuous, interrupt on wrap
```
`TB0_SETUP` (`sol.h`) is `TBSSEL__ACLK|ID__8|MC__CONTINUOUS|TBCLR|TBIE`. At 512 Hz the 16-bit count wraps every
65,536 / 512 = 128 s, and the wrap's interrupt wakes `main` so it can kick the watchdog during long idle spells
(below). Step 4 later used the same timer's CCR0 for the button debounce tick.

**6. Start the watchdog: on ACLK, 256 s.**
```asm
        mov.w   #WDT_RUN, &WDTCTL
```
`WDT_RUN` (`sol.h`) is `WDTPW|WDTSSEL__ACLK|WDTIS__8192K|WDTCNTCL`: the password, ACLK as its clock, a time-out
of 2^23 counts (8,388,608 / 32,768 = 256 s), and clear the count. Written again, the same value is the kick.
ACLK, not SMCLK: in watchdog mode the chip keeps the watchdog's clock running even in LPM3, so on SMCLK it would
keep the DCO on and the sleep current would rise from about 2 µA to hundreds.

## 3. The TB0 wrap interrupt

```asm
        .section __interrupt_vector_timer0_b1, "ax", @progbits ; TIMER0_B1_VECTOR (42)
        .word   tb0_wrap_isr
        ...
tb0_wrap_isr:
        tst.w   &TB0IV                                  ; reading TB0IV clears TBIFG
        bic.w   #LPM3_bits, 0(SP)                       ; wake main
        reti
```
- **The vector.** TB0 has two: `TIMER0_B0` (vector 43) for CCR0 alone, and `TIMER0_B1` (vector 42) for CCR1–2
  and the overflow, shared and told apart by `TB0IV`. The wrap is on vector **42**. (Putting it on 43 was a
  bug in the first version: the wrap then had no handler, and the chip crashed at 128 s.)
- **`TB0IV`.** Reading it clears the flag of the source it reports. Without the read the flag stays set, the
  interrupt repeats for ever, and the watchdog eventually resets the chip.
- **Waking `main`.** An interrupt saves SR on the stack and `reti` restores it. Clearing the LPM3 bits in the
  *saved* SR (at `0(SP)`, as this routine pushes nothing) means `reti` returns to `main` awake.
- It uses no registers, so it saves none. (An interrupt must save every register it uses, R11–R15 included.)

## 4. `main`'s sleep loop

```asm
main:
        call    #system
loop:
        mov.w   #WDT_RUN, &WDTCTL                       ; kick the watchdog
        bis.w   #LPM3_bits|GIE, SR                      ; sleep in LPM3, interrupts on
        nop
        jmp     loop
```
- LPM3: the CPU, MCLK and SMCLK stop; ACLK (REFO) keeps running for TB0, the watchdog and (from step 2)
  EXTCOMIN.
- Setting GIE and the LPM3 bits in one instruction means an interrupt can't slip in between enabling interrupts
  and going to sleep. TI asks for a `nop` after it.
- Each wake-up goes round the loop once: kick the watchdog, sleep again. With nothing else happening, TB0's wrap
  wakes it every 128 s, well inside the watchdog's 256 s.

Step 4 replaced this loop with the event loop (`dint`, check the queue, sleep; handle each event), which keeps
the same kick and the same sleep instruction.

## 5. Checking it

On the simulator's runner, `msp430_run` (`sim/picsimlab-msp430/src/sim_backend/msp430/tests/`), with the build's
hex file:

| Check | How | Result |
| --- | --- | --- |
| MCLK 8 MHz | the runner's final line, `MCLK=` | `MCLK=7995392 Hz` |
| Asleep in LPM3 | the runner's `SR=`: CPUOFF, SCG0 and SCG1 (0x00D0) set, and GIE (0x0008) | `SR=00D8` (or `00DB` with carry and zero) |
| Few cycles used | `ran N s: M MCLK cycles`: a sleeping chip runs a handful of instructions per wake-up | a few hundred cycles a second |
| No reset over 10 minutes idle | `--seconds 600 --tick 1e5 --peek 015E:1`: `SYSRSTIV` (0x015E) still 0 | 0 |
| A hang is reset | a test build with an endless loop (`jmp $`) after `call #system`, run 300 s | reset within 256 s; `SYSRSTIV` 0x16 (watchdog time-out) |

For the hang test, the debugger showed the chip back at the start-up code after 256 s, with `SYSRSTIV` 0x16.
(The runner's `--peek` reads memory, not every peripheral register's live state; read `SYSRSTIV` in the
debugger to be sure.)

In NetBeans, Debug stops at breakpoints in `system`; Variables shows `CSCTL0`–`CSCTL8`, `TB0CTL`, `WDTCTL` and the
port registers by name.

## 6. Lessons from getting it working

Each of these was a real bug in the first version, caught by the checks above or a review:

- **`call system` needs a `#`:** `call #system`. Without it the CPU jumps to the address *stored at* `system`
  (indirect), which is the code of its first instruction, not an address. The same slip came back in later
  steps; search for `call ` without `#` after editing.
- **`WDTCTL = ...` is not an instruction.** In `as`, `name = value` defines a symbol; it doesn't write the
  register. Use `mov.w #..., &WDTCTL`.
- **Every `WDTCTL` write needs `WDTPW`,** the kick included. A kick written as `#WDTCNTCL` alone resets the chip.
- **The TB0 wrap's vector is 42 (`TIMER0_B1`), not 43.** See section 3.
- **Pins before `LOCKLPM5`.** Releasing the lock first lets the pins show their reset states, and in later
  steps a missing release left the display's pins dead (step 2).
- **`.s` files skip the preprocessor.** `#include <msp430.h>` only works in `.S` (capital S) files, so every
  source file is `.S`. The plugin's template now makes `.S` files and warns about an `#include` in a `.s` one.

## Not in step 1

From the plan, left for later steps:

- **Counting watchdog resets:** reading `SYSRSTIV` at start-up and keeping a count in `.persistent`, shown with
  the statistics (step 8 or 9, with saving).
- **A catch-all for unused interrupt vectors**, so a stray interrupt resets cleanly instead of jumping to 0.
