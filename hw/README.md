	# Solitaire handheld: hardware

A pocket solitaire game: an MSP430 microcontroller drives a Sharp memory LCD, runs from two AA cells,
and is played with push buttons. The memory LCD holds its image without refresh, so the board spends
almost all of its time asleep and wakes only when a button is pressed.

The schematic is in `sol/` and passes KiCad's ERC; the PCB hasn't been laid out. The parts library is in `lib/`.

## Block diagram

```
 2x AA ──► TPS63900 buck-boost ──► 3.0 V rail ──┬──► MSP430FR2355 (MCU)
 (1.8-3.2 V)                                    │       │  SPI + EXTCOMIN + DISP
                                                │       ▼
                                                └──► Sharp LS013B7DH05 memory LCD
                                                        (via 10-pin FPC connector)
 Buttons ──► MSP430 port pins (interrupt on press; wake from sleep)
 Spy-Bi-Wire header ──► MSP430 (programming and debug)
```

## Parts

| Function | Part | Why |
| --- | --- | --- |
| Microcontroller | TI MSP430FR2355TDBT (TSSOP-38) | 32 KB FRAM, 4 KB RAM, 34 GPIO, sleeps at about 1.2 µA (LPM3, 32 kHz crystal running). Free GCC toolchain. |
| Display | Sharp LS013B7DH05, 1.26 in, 144 × 168, monochrome memory LCD | Holds its image at near-zero power, readable in daylight, 3 V supply, framebuffer fits in the MCU's RAM. |
| Display connector | Panasonic AYF531035 (Y5B, 10 contacts, 0.5 mm pitch) | Sharp's first recommendation for this display. Contacts top and bottom, so the FPC can go in either face down. |
| Power | TI TPS63900 buck-boost (WSON-10) | Holds a steady rail as two AA cells run from 3.2 V down to about 1.8 V, with a quiescent current of about 75 nA. |
| Inductor | Murata DFE201612E-2R2M, 2.2 µH, 2.0 × 1.6 × 1.2 mm | On TI's recommended list for the TPS63900. Saturation current 2.4 A, well above the 1 A TI requires at this board's 100 mA current limit (and enough for the 2 A needed if the limit is ever removed); DC resistance 116 mΩ. |
| Regulator capacitors | Murata GRM188R60J106ME47 (10 µF in) and GRM187R60J226ME15 (22 µF out), 6.3 V X5R 0603 | TI's recommended parts and its typical-application values. |
| Display capacitors | Murata GRM188R71C104KA01 (0.1 µF) and 2 × GRM188R71A105KA61 (1 µF), X7R 0603 | Sharp's Figure 9-1: 0.1 µF DISP to VSS, 1 µF VDDA to VSSA, 1 µF VDD to VSS. |
| Regulator configuration | Yageo RC0603FR-07 series, 1%: 20.5 kΩ (CFG1), 511 Ω (CFG2), 13.3 kΩ (CFG3) | Set 3.0 V out and a 100 mA input current limit; see Power below. |
| Battery | 2 × AA in an open holder with a JST-PH lead (e.g. Adafruit #4194) | Cheap, easy to find, and long-lasting at this current draw. |
| Buttons | ALPS SKRPACE010 tact switches | Low-profile, easy to source. |
| Programming | 1 × 4, 2.54 mm Spy-Bi-Wire header: 3V0, TEST/SBWTCK, RST/SBWTDIO, GND | Same order as a LaunchPad eZ-FET's 3V3/TST/RST/GND jumpers, so four jumper wires run straight across. Needs a 47 kΩ pull-up on RST/SBWTDIO and at most 1.1 nF from it to GND (1 nF). |

## Design decisions

### Microcontroller: MSP430FR2355

The game needs a framebuffer in RAM, very low sleep current, and enough pins for a display and a set of
buttons. The FR2355's 4 KB of RAM holds the display's 3,024-byte framebuffer with about 1 KB left for the
stack and game state. If that gets tight, the framebuffer can move to FRAM, which writes at RAM-like speed.

ATtiny1607 and ATtiny3226 were considered. The ATtiny1607's 1 KB of RAM can't hold a framebuffer, and the
ATtiny3226 offered no clear advantage.

### Display: Sharp LS013B7DH05

A memory LCD keeps its image with the CPU asleep and draws microamps, which suits a battery game that
spends most of its time waiting for the player.

| Display | Verdict |
| --- | --- |
| **LS013B7DH05**, 144 × 168 | **Chosen.** 3 V, framebuffer fits in RAM. |
| LS013B7DH03, 128 × 128 | Same pinout and supply, fewer pixels, and Mouser lists it as obsolete. |
| LS027B7DH01, 400 × 240 | Needs a 5 V supply and a 12 KB framebuffer, which doesn't fit in RAM. |
| LS013B7DH06 (colour) | Uncertain availability. |
| JDI LPM013M126A (colour) | Uncertain availability. |

What the display needs from the board:

- **EXTCOMIN at 57–66 Hz.** The display needs its common electrode toggled to avoid DC damage to the
  liquid crystal. That's too often to wake the CPU for. Instead, a Timer_B output clocked from the 32 kHz
  ACLK drives the EXTCOMIN pin directly. It keeps running in LPM3 with the CPU asleep. **EXTCOMIN must
  therefore go on a timer output pin**: P2.0/P2.1 (TB1.1/TB1.2) or P5.0/P5.1 (TB2.1/TB2.2). Those leave both
  SPI ports free.
- **Three capacitors at the connector** (Figure 9-1): 0.1 µF from DISP to VSS, and 1 µF each from VDDA to VSSA
  and VDD to VSS.
- **EXTMODE tied high**, to select the EXTCOMIN pin as the COM source rather than a bit in the SPI data.
- **Supply 2.7–3.3 V.** The rail must stay in this window; 3.0 V suits both the display and the MCU.
- **Glass**: 24.68 × 30.0 × 0.745 mm, viewing area 20.88 × 24.36 mm (taller than it is wide).

### Buttons

Discrete buttons are easy to source and need no custom knob or cap, which keeps the case thin. The display
uses only 5 of the FR2355's 34 GPIO, so there are plenty to spare.

All four ports (P1–P4) have pin interrupts that wake the MCU from every low-power mode, including
LPMx.5, so buttons can go on any of them. The schematic has 16: nine for the stacks (P1.0–P1.6, P2.0–P2.1),
four for the suits (P2.2–P2.5) and three more on P3.0–P3.2. Each switches to GND, using the MCU's internal
pull-ups.

### Power

Two AA cells feed the TPS63900, which bucks or boosts to a fixed 3.0 V rail across the cells' whole
discharge range.

The inductor must be 2.2 µH. TI recommends five: Coilcraft XFL4020-222ME, Bourns SRN3015TA-2R2M, and Murata
DFE252010F-2R2M, DFE201612E-2R2M and DFE201210U-2R2M. The DFE201612E is the smallest with margin; the
2.0 × 1.2 mm DFE201210U saturates at exactly TI's 2 A minimum, without the 20% headroom TI recommends. If
efficiency at heavier loads ever matters more than board space, the DFE252010F (2.5 × 2.0 × 1.0 mm, 97 mΩ) is
the swap; at this board's few-milliamp load the difference is small.

The regulator reads three resistors to ground once at power-up (Tables 7-2 and 7-3 of TI's datasheet):

| Pin | Resistor | Sets |
| --- | --- | --- |
| CFG1 | 20.5 kΩ | 3.0 V output when SEL is high |
| CFG2 | 511 Ω | 100 mA input current limit |
| CFG3 | 13.3 kΩ | 3.0 V output when SEL is low |

Both output settings are 3.0 V, so SEL's level doesn't matter; tie it to GND. Tie EN to VIN. Neither pin may be
left open. The 100 mA limit still allows about 50 mA out with nearly flat cells at 1.8 V, far more than the
board draws, and limits the input to about 26 mA if the output is shorted. Use resistors of 1% or better and
200 ppm/°C or better, keep the CFG traces short, and put no capacitance on them (10 pF maximum).

There's no power switch: the board is always on and relies on sleep. When programming, don't connect the
debugger's 3.3 V while the batteries are in, or it will fight the regulator's output: either remove the batteries
and let the debugger power the board (3.3 V is within the MCU's and display's limits), or leave its 3V3 wire off. The TPS63900 isn't protected against a
reversed battery, so either add protection (a P-channel MOSFET costs almost no voltage) or check the battery
lead's polarity against the connector's pin 1 before first power-up.

### Display connector and FPC routing

The AYF531035 has contacts on both sides, so the FPC can go in either face down:

- **Display face up, FPC straight into the connector** (FPC contacts facing the board): FPC lead 1 meets
  connector pad 1. The library's symbol and footprint assume this.
- **FPC bent back so the display sits over the connector**: the leads reverse (lead 1 meets pad 10), and the
  schematic's pin numbers must be swapped.

Sharp's limits on the FPC: bend only 0.8–6.0 mm from the glass edge, inner radius at least 0.45 mm, never
toward the display face, and no more than three bends.

## Files

- `lib/`: KiCad 9 symbols, footprints and 3D models for the parts above; see `lib/README.md`. Everything there is
  generated by scripts, so edit the scripts and rerun them.
- `../docs/datasheets/`: datasheets for the MCU, regulator, displays and connector.

Firmware toolchain: TI MSP430-GCC 9.3.1.11 at `~/ti/msp430-gcc` (`-mmcu=msp430fr2355`). The mspdebug source is in
`~/ti/src/mspdebug` but isn't built yet; it needs `libusb-dev` and `libreadline-dev`.

## Open items

- Start the schematic and PCB.
- Check the AYF531035 footprint against Panasonic's product specification for the exact part.
- Decide whether to add reverse-battery protection.
- Design the case around the board and the display's outline (`lib/3d/LS013B7DH05.step`).
