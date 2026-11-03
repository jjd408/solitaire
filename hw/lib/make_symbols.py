#!/usr/bin/env python3
"""Writes solitaire.kicad_sym, the project's KiCad symbol library.

MSP430FR2355TDBT: from Figure 4-3 (38-pin DBT pinout) of TI's datasheet SLASEC4D, in
../../docs/datasheets/msp430fr2355.pdf. Pins are grouped by function rather than package order:
power and Spy-Bi-Wire on the left with ports P1 and P2; ports P3, P4 and P5 on the right.
Run it again after editing the pin tables below.
"""

# (pin number, name, KiCad electrical type)
LEFT = [
    (10, "DVCC", "power_in"),
    (11, "DVSS", "power_in"),
    None,
    (8, "TEST/SBWTCK", "input"),
    (9, "~{RST}/NMI/SBWTDIO", "bidirectional"),
    None,
    (7, "P1.0/UCB0STE/SMCLK/COMP0.0/A0/Veref+", "bidirectional"),
    (6, "P1.1/UCB0CLK/ACLK/OA0O/COMP0.1/A1", "bidirectional"),
    (5, "P1.2/UCB0SIMO/UCB0SDA/TB0TRG/OA0-/A2/Veref-", "bidirectional"),
    (4, "P1.3/UCB0SOMI/UCB0SCL/OA0+/A3", "bidirectional"),
    (31, "P1.4/UCA0STE/TCK/A4", "bidirectional"),
    (30, "P1.5/UCA0CLK/TMS/OA1O/A5", "bidirectional"),
    (29, "P1.6/UCA0RXD/UCA0SOMI/TB0.1/TDI/TCLK/OA1-/A6", "bidirectional"),
    (28, "P1.7/UCA0TXD/UCA0SIMO/TB0.2/TDO/OA1+/A7/VREF+", "bidirectional"),
    None,
    (27, "P2.0/TB1.1/COMP0.O", "bidirectional"),
    (26, "P2.1/TB1.2/COMP1.O", "bidirectional"),
    (25, "P2.2/TB1CLK", "bidirectional"),
    (24, "P2.3/TB1TRG", "bidirectional"),
    (15, "P2.4/COMP1.1", "bidirectional"),
    (14, "P2.5/COMP1.0", "bidirectional"),
    (13, "P2.6/MCLK/XOUT", "bidirectional"),
    (12, "P2.7/TB0CLK/XIN", "bidirectional"),
]
RIGHT = [
    (3, "P3.0/MCLK", "bidirectional"),
    (2, "P3.1/OA2O", "bidirectional"),
    (1, "P3.2/OA2-", "bidirectional"),
    (38, "P3.3/OA2+", "bidirectional"),
    (35, "P3.4/SMCLK", "bidirectional"),
    (34, "P3.5/OA3O", "bidirectional"),
    (33, "P3.6/OA3-", "bidirectional"),
    (32, "P3.7/OA3+", "bidirectional"),
    # Gap so port P4's names sit opposite port P2's short ones, not P1's long ones.
    None, None, None, None, None, None, None,
    (23, "P4.0/UCA1STE/ISOTXD/ISORXD", "bidirectional"),
    (22, "P4.1/UCA1CLK", "bidirectional"),
    (21, "P4.2/UCA1RXD/UCA1SOMI", "bidirectional"),
    (20, "P4.3/UCA1TXD/UCA1SIMO", "bidirectional"),
    (19, "P4.4/UCB1STE", "bidirectional"),
    (18, "P4.5/UCB1CLK", "bidirectional"),
    (17, "P4.6/UCB1SIMO/UCB1SDA", "bidirectional"),
    (16, "P4.7/UCB1SOMI/UCB1SCL", "bidirectional"),
    None,
    (37, "P5.0/TB2.1/MFM.RX/A8", "bidirectional"),
    (36, "P5.1/TB2.2/MFM.TX/A9", "bidirectional"),
]

PITCH = 2.54
HALF_WIDTH = 33.02  # wide enough for the longest pin names on each side
PIN_LEN = 2.54


def pin(number, name, kind, x, y, angle):
    return (f'\t\t\t(pin {kind} line (at {x:.2f} {y:.2f} {angle}) (length {PIN_LEN})\n'
            f'\t\t\t\t(name "{name}" (effects (font (size 1.27 1.27))))\n'
            f'\t\t\t\t(number "{number}" (effects (font (size 1.27 1.27))))\n'
            f'\t\t\t)\n')


def prop(key, value, x, y, hide=False, justify=None):
    hidden = " (hide yes)" if hide else ""
    just = f" (justify {justify})" if justify else ""
    return (f'\t\t(property "{key}" "{value}" (at {x:.2f} {y:.2f} 0)\n'
            f'\t\t\t(effects (font (size 1.27 1.27)){just}{hidden})\n\t\t)\n')


def msp430fr2355tdbt():
    rows = max(len(LEFT), len(RIGHT))
    top = (rows - 1) * PITCH / 2
    top = round(top / PITCH) * PITCH  # keep pins on the 2.54mm grid
    body_top, body_bottom = top + PITCH, top - rows * PITCH
    numbers = [p[0] for p in LEFT + RIGHT if p]
    assert sorted(numbers) == list(range(1, 39)), "every pin 1-38 exactly once"
    s = '\t(symbol "MSP430FR2355TDBT"\n\t\t(exclude_from_sim no) (in_bom yes) (on_board yes)\n'
    s += prop("Reference", "U", -HALF_WIDTH, body_top + 1.27, justify="left")
    s += prop("Value", "MSP430FR2355TDBT", HALF_WIDTH, body_top + 1.27, justify="right")
    s += prop("Footprint", "Package_SO:TSSOP-38_4.4x9.7mm_P0.5mm", 0, body_bottom - 3.81, True)
    s += prop("Datasheet", "https://www.ti.com/lit/ds/symlink/msp430fr2355.pdf", 0, body_bottom - 6.35, True)
    s += prop("Description", "MSP430FR2355 mixed-signal microcontroller, 32KB FRAM, 4KB RAM, 24MHz, TSSOP-38", 0,
              body_bottom - 8.89, True)
    s += prop("ki_keywords", "MSP430 FRAM low power microcontroller", 0, 0, True)
    s += prop("ki_fp_filters", "TSSOP*4.4x9.7mm*P0.5mm*", 0, 0, True)
    s += ('\t\t(symbol "MSP430FR2355TDBT_0_1"\n'
          f'\t\t\t(rectangle (start {-HALF_WIDTH:.2f} {body_top:.2f}) (end {HALF_WIDTH:.2f} {body_bottom:.2f})\n'
          '\t\t\t\t(stroke (width 0.254) (type default)) (fill (type background))\n\t\t\t)\n\t\t)\n')
    s += '\t\t(symbol "MSP430FR2355TDBT_1_1"\n'
    for side, x, angle in ((LEFT, -HALF_WIDTH - PIN_LEN, 0), (RIGHT, HALF_WIDTH + PIN_LEN, 180)):
        for i, p in enumerate(side):
            if p:
                s += pin(p[0], p[1], p[2], x, top - i * PITCH, angle)
    s += '\t\t)\n\t\t(embedded_fonts no)\n\t)\n'
    return s


# The Sharp memory LCDs' 10-pin FPC, from Table 6-1 of Sharp spec LCP-2111042 (LS013B7DH03) and
# spec LD-26912A (LS013B7DH05), in ../../docs/datasheets/. Both use the same pinout. Signals on the
# left, power on the right.
LCD_LEFT = [
    (1, "SCLK", "input"),
    (2, "SI", "input"),
    (3, "SCS", "input"),
    (4, "EXTCOMIN", "input"),
    (5, "DISP", "input"),
    (8, "EXTMODE", "input"),
]
LCD_RIGHT = [
    (7, "VDD", "power_in"),
    (6, "VDDA", "power_in"),
    None,
    None,
    (9, "VSS", "power_in"),
    (10, "VSSA", "power_in"),
]


def sharp_lcd(name, description, footprint=""):
    half = 10.16
    top = 6.35
    rows = len(LCD_LEFT)
    body_top, body_bottom = top + PITCH, top - rows * PITCH
    s = f'\t(symbol "{name}"\n\t\t(exclude_from_sim no) (in_bom yes) (on_board yes)\n'
    s += prop("Reference", "DS", -half, body_top + 1.27, justify="left")
    s += prop("Value", name, half, body_top + 1.27, justify="right")
    s += prop("Footprint", footprint, 0, body_bottom - 1.27, True)
    s += prop("Datasheet", "", 0, body_bottom - 3.81, True)
    s += prop("Description", description, 0, body_bottom - 6.35, True)
    s += prop("ki_keywords", "Sharp memory LCD display SPI", 0, 0, True)
    s += (f'\t\t(symbol "{name}_0_1"\n'
          f'\t\t\t(rectangle (start {-half:.2f} {body_top:.2f}) (end {half:.2f} {body_bottom:.2f})\n'
          '\t\t\t\t(stroke (width 0.254) (type default)) (fill (type background))\n\t\t\t)\n\t\t)\n')
    s += f'\t\t(symbol "{name}_1_1"\n'
    for side, x, angle in ((LCD_LEFT, -half - PIN_LEN, 0), (LCD_RIGHT, half + PIN_LEN, 180)):
        for i, p in enumerate(side):
            if p:
                s += pin(p[0], p[1], p[2], x, top - i * PITCH, angle)
    s += '\t\t)\n\t\t(embedded_fonts no)\n\t)\n'
    return s


# The TPS63900's inductor: KiCad's Device:L drawing, with the part's footprint, value and datasheet filled in.
def murata_dfe201612e_2r2m():
    name = "L_DFE201612E-2R2M"
    s = (f'\t(symbol "{name}"\n\t\t(pin_numbers (hide yes))\n\t\t(pin_names (offset 1.016) (hide yes))\n'
         '\t\t(exclude_from_sim no) (in_bom yes) (on_board yes)\n')
    s += prop("Reference", "L", 1.905, 1.27, justify="left")
    s += prop("Value", "2.2uH", 1.905, -1.27, justify="left")
    s += prop("Footprint", "solitaire:L_Murata_DFE201612E", 0, 0, True)
    s += prop("Datasheet", "https://www.murata.com/en/products/productdetail?partno=DFE201612E-2R2M%23", 0, 0, True)
    s += prop("Description", "Murata DFE201612E-2R2M 2.2uH metal-alloy power inductor, Isat 2.4A, 116mOhm, "
              "2.0x1.6x1.2mm; the TPS63900's inductor", 0, 0, True)
    s += prop("MPN", "DFE201612E-2R2M=P2", 0, 0, True)
    s += prop("ki_keywords", "inductor power Murata TPS63900", 0, 0, True)
    s += f'\t\t(symbol "{name}_0_1"\n'
    for top in (2.54, 1.27, 0, -1.27):
        s += (f'\t\t\t(arc (start 0 {top:.2f}) (mid 0.6323 {top - 0.635:.3f}) (end 0 {top - 1.27:.2f})\n'
              '\t\t\t\t(stroke (width 0) (type default)) (fill (type none))\n\t\t\t)\n')
    s += f'\t\t)\n\t\t(symbol "{name}_1_1"\n'
    s += pin(1, "1", "passive", 0, 3.81, 270).replace(f"(length {PIN_LEN})", "(length 1.27)")
    s += pin(2, "2", "passive", 0, -3.81, 90).replace(f"(length {PIN_LEN})", "(length 1.27)")
    s += '\t\t)\n\t\t(embedded_fonts no)\n\t)\n'
    return s


# Ceramic capacitors: KiCad's Device:C drawing with the part filled in. All are 0603, so they use KiCad's own
# footprint and 3D model.
#   TPS63900 input and output: Tables 8-4 and 8-3 of TI's datasheet.
#   MSP430 RST/SBWTDIO: 1nF to GND (Table 4-4: at most 1.1nF with Spy-Bi-Wire); DVCC bypass 4.7uF (section 4.1
#   asks for 4.7-10uF plus 0.1uF).
#   LS013B7DH05: Figure 9-1 of Sharp's spec LD-26912A asks for "rank B" (+/-10%, like X7R) ceramics: 0.1uF from
#   DISP to VSS, and 1uF each from VDDA to VSSA and VDD to VSS.
def murata_cap(name, value, mpn, description, keywords):
    s = (f'\t(symbol "{name}"\n\t\t(pin_numbers (hide yes))\n\t\t(pin_names (offset 0.254) (hide yes))\n'
         '\t\t(exclude_from_sim no) (in_bom yes) (on_board yes)\n')
    s += prop("Reference", "C", 0.635, 2.54, justify="left")
    s += prop("Value", value, 0.635, -2.54, justify="left")
    s += prop("Footprint", "Capacitor_SMD:C_0603_1608Metric", 0, 0, True)
    s += prop("Datasheet", f"https://www.murata.com/en/products/productdetail?partno={mpn}%23", 0, 0, True)
    s += prop("Description", description, 0, 0, True)
    s += prop("MPN", mpn, 0, 0, True)
    s += prop("ki_keywords", "capacitor ceramic MLCC Murata " + keywords, 0, 0, True)
    s += f'\t\t(symbol "{name}_0_1"\n'
    for y in (0.762, -0.762):
        s += (f'\t\t\t(polyline (pts (xy -2.032 {y}) (xy 2.032 {y}))\n'
              '\t\t\t\t(stroke (width 0.508) (type default)) (fill (type none))\n\t\t\t)\n')
    s += f'\t\t)\n\t\t(symbol "{name}_1_1"\n'
    s += pin(1, "~", "passive", 0, 3.81, 270).replace(f"(length {PIN_LEN})", "(length 2.794)")
    s += pin(2, "~", "passive", 0, -3.81, 90).replace(f"(length {PIN_LEN})", "(length 2.794)")
    s += '\t\t)\n\t\t(embedded_fonts no)\n\t)\n'
    return s


# Yageo RC series 0603 resistors, 1% and 100ppm/C: KiCad's Device:R drawing with the part filled in.
#   TPS63900 configuration: Tables 7-2 and 7-3 of TI's datasheet give 3.0V out whichever level SEL is at, and a
#   100mA input current limit. TI asks for 1% or better and 200ppm/C or better.
#   MSP430 RST/SBWTDIO pull-up: 47k, from Table 4-4 of the MSP430FR2355 datasheet.
def yageo_resistor(name, value, mpn, purpose, keywords="TPS63900 CFG configuration"):
    s = (f'\t(symbol "{name}"\n\t\t(pin_numbers (hide yes))\n\t\t(pin_names (offset 0) (hide yes))\n'
         '\t\t(exclude_from_sim no) (in_bom yes) (on_board yes)\n')
    s += prop("Reference", "R", 2.032, 1.27, justify="left")
    s += prop("Value", value, 2.032, -1.27, justify="left")
    s += prop("Footprint", "Resistor_SMD:R_0603_1608Metric", 0, 0, True)
    s += prop("Datasheet", "https://www.yageo.com/upload/media/product/productsearch/datasheet/rchip/"
              "PYu-RC_Group_51_RoHS_L_12.pdf", 0, 0, True)
    s += prop("Description", f"Yageo {value} 1% 100ppm/C 0603 thick-film resistor; {purpose}", 0, 0, True)
    s += prop("MPN", mpn, 0, 0, True)
    s += prop("ki_keywords", "resistor " + keywords, 0, 0, True)
    s += (f'\t\t(symbol "{name}_0_1"\n'
          '\t\t\t(rectangle (start -1.016 -2.54) (end 1.016 2.54)\n'
          '\t\t\t\t(stroke (width 0.254) (type default)) (fill (type none))\n\t\t\t)\n'
          f'\t\t)\n\t\t(symbol "{name}_1_1"\n')
    s += pin(1, "~", "passive", 0, 3.81, 270).replace(f"(length {PIN_LEN})", "(length 1.27)")
    s += pin(2, "~", "passive", 0, -3.81, 90).replace(f"(length {PIN_LEN})", "(length 1.27)")
    s += '\t\t)\n\t\t(embedded_fonts no)\n\t)\n'
    return s


# The game's buttons: KiCad's Switch:SW_Push drawing with the ALPS SKRPACE010 filled in. The footprint joins
# ALPS's terminals 1 and 2 as pad 1, and 3 and 4 as pad 2.
def alps_skrpace010():
    name = "SW_SKRPACE010"
    s = (f'\t(symbol "{name}"\n\t\t(pin_numbers (hide yes))\n\t\t(pin_names (offset 1.016) (hide yes))\n'
         '\t\t(exclude_from_sim no) (in_bom yes) (on_board yes)\n')
    s += prop("Reference", "SW", 1.27, 2.54, justify="left")
    s += prop("Value", "SKRPACE010", 0, -1.524, False)
    s += prop("Footprint", "solitaire:SW_Alps_SKRPACE010", 0, 5.08, True)
    s += prop("Datasheet", "https://tech.alpsalpine.com/e/products/detail/SKRPACE010/", 0, 5.08, True)
    s += prop("Description", "ALPS SKRPACE010 tact switch, 4.2x3.2x2.5mm, 2.55N, 50mA 16V", 0, 0, True)
    s += prop("MPN", "SKRPACE010", 0, 0, True)
    s += prop("ki_keywords", "switch push button tact ALPS", 0, 0, True)
    s += (f'\t\t(symbol "{name}_0_1"\n'
          '\t\t\t(circle (center -2.032 0) (radius 0.508)\n'
          '\t\t\t\t(stroke (width 0) (type default)) (fill (type none))\n\t\t\t)\n'
          '\t\t\t(polyline (pts (xy 0 1.27) (xy 0 3.048))\n'
          '\t\t\t\t(stroke (width 0) (type default)) (fill (type none))\n\t\t\t)\n'
          '\t\t\t(circle (center 2.032 0) (radius 0.508)\n'
          '\t\t\t\t(stroke (width 0) (type default)) (fill (type none))\n\t\t\t)\n'
          '\t\t\t(polyline (pts (xy 2.54 1.27) (xy -2.54 1.27))\n'
          '\t\t\t\t(stroke (width 0) (type default)) (fill (type none))\n\t\t\t)\n'
          f'\t\t)\n\t\t(symbol "{name}_1_1"\n')
    s += pin(1, "1", "passive", -5.08, 0, 0)
    s += pin(2, "2", "passive", 5.08, 0, 180)
    s += '\t\t)\n\t\t(embedded_fonts no)\n\t)\n'
    return s


# The Spy-Bi-Wire programming header: a 1x4 2.54mm pin header, in the order of a LaunchPad's eZ-FET isolation
# jumpers (3V3, TST, RST, GND) so four jumper wires run straight across. KiCad's own footprint and 3D model.
# TI's pin connection table also asks for a 47k pull-up on RST/SBWTDIO and at most 1.1nF from it to GND.
SBW_PINS = [
    (1, "3V0", "passive"),
    (2, "TEST/SBWTCK", "passive"),
    (3, "~{RST}/SBWTDIO", "passive"),
    (4, "GND", "passive"),
]


def sbw_header():
    name = "Conn_SBW_1x04"
    half = 8.89
    top = 3.81
    body_top, body_bottom = top + PITCH, top - len(SBW_PINS) * PITCH
    s = f'\t(symbol "{name}"\n\t\t(exclude_from_sim no) (in_bom yes) (on_board yes)\n'
    s += prop("Reference", "J", -half, body_top + 1.27, justify="left")
    s += prop("Value", "SBW", half, body_top + 1.27, justify="right")
    s += prop("Footprint", "Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Vertical", 0, body_bottom - 1.27, True)
    s += prop("Datasheet", "https://www.ti.com/lit/ug/slau647/slau647.pdf", 0, body_bottom - 3.81, True)
    s += prop("Description", "Spy-Bi-Wire programming header, 1x4 2.54mm, pinned to match a LaunchPad eZ-FET's "
              "3V3/TST/RST/GND jumpers", 0, body_bottom - 6.35, True)
    s += prop("ki_keywords", "connector header programming debug MSP430 Spy-Bi-Wire SBW", 0, 0, True)
    s += prop("ki_fp_filters", "PinHeader*1x04*", 0, 0, True)
    s += (f'\t\t(symbol "{name}_0_1"\n'
          f'\t\t\t(rectangle (start {-half:.2f} {body_top:.2f}) (end {half:.2f} {body_bottom:.2f})\n'
          '\t\t\t\t(stroke (width 0.254) (type default)) (fill (type background))\n\t\t\t)\n\t\t)\n')
    s += f'\t\t(symbol "{name}_1_1"\n'
    for i, (number, pin_name, kind) in enumerate(SBW_PINS):
        s += pin(number, pin_name, kind, -half - PIN_LEN, top - i * PITCH, 0)
    s += '\t\t)\n\t\t(embedded_fonts no)\n\t)\n'
    return s


def main():
    with open("solitaire.kicad_sym", "w") as f:
        f.write('(kicad_symbol_lib\n\t(version 20241209)\n\t(generator "make_symbols.py")\n'
                '\t(generator_version "9.0")\n')
        f.write(msp430fr2355tdbt())
        f.write(sharp_lcd("LS013B7DH03", "Sharp 1.28in 128x128 memory LCD on a 10-pin 0.5mm FPC; place the FPC "
                          "connector's footprint here (Sharp recommends Molex 51441-1093 or SMK CFP-4610-0150F)"))
        f.write(sharp_lcd("LS013B7DH05", "Sharp 1.26in 144x168 memory LCD, 3V, on a 10-pin 0.5mm FPC, plugged into a "
                          "Panasonic AYF531035 connector (the footprint)",
                          "solitaire:Panasonic_AYF531035_1x10-1MP_P0.5mm_Horizontal"))
        f.write(murata_dfe201612e_2r2m())
        f.write(murata_cap("C_GRM188R60J106ME47", "10uF", "GRM188R60J106ME47",
                           "Murata 10uF 6.3V X5R 0603 ceramic capacitor; the TPS63900's input capacitor", "TPS63900"))
        f.write(murata_cap("C_GRM187R60J226ME15", "22uF", "GRM187R60J226ME15",
                           "Murata 22uF 6.3V X5R 0603 ceramic capacitor; the TPS63900's output capacitor", "TPS63900"))
        f.write(murata_cap("C_GRM188R71C104KA01", "0.1uF", "GRM188R71C104KA01",
                           "Murata 0.1uF 16V X7R 0603 ceramic capacitor; the LS013B7DH05's DISP capacitor (C1 in "
                           "Sharp's Figure 9-1, DISP to VSS)", "LS013B7DH05 display"))
        f.write(murata_cap("C_GRM188R71A105KA61", "1uF", "GRM188R71A105KA61",
                           "Murata 1uF 10V X7R 0603 ceramic capacitor; the LS013B7DH05's VDDA and VDD capacitors (C2 "
                           "VDDA to VSSA, C3 VDD to VSS in Sharp's Figure 9-1)", "LS013B7DH05 display"))
        f.write(yageo_resistor("R_CFG1_20k5", "20.5k", "RC0603FR-0720K5L",
                                   "TPS63900 CFG1 to GND: 3.0V output with SEL high"))
        f.write(yageo_resistor("R_CFG2_511", "511", "RC0603FR-07511RL",
                                   "TPS63900 CFG2 to GND: 100mA input current limit (with R_CFG1 20.5k)"))
        f.write(yageo_resistor("R_CFG3_13k3", "13.3k", "RC0603FR-0713K3L",
                                   "TPS63900 CFG3 to GND: 3.0V output with SEL low"))
        f.write(yageo_resistor("R_RST_47k", "47k", "RC0603FR-0747KL",
                               "MSP430 RST/SBWTDIO pull-up to DVCC", "MSP430 reset pull-up RST SBWTDIO"))
        f.write(murata_cap("C_GRM188R71H102KA01", "1nF", "GRM188R71H102KA01",
                           "Murata 1nF 50V X7R 0603 ceramic capacitor; MSP430 RST/SBWTDIO to GND (at most 1.1nF "
                           "for Spy-Bi-Wire)", "MSP430 reset RST SBWTDIO"))
        f.write(murata_cap("C_GRM188R60J475KE19", "4.7uF", "GRM188R60J475KE19",
                           "Murata 4.7uF 6.3V X5R 0603 ceramic capacitor; MSP430 DVCC bypass", "MSP430 DVCC bypass"))
        f.write(alps_skrpace010())
        f.write(sbw_header())
        f.write(')\n')


if __name__ == "__main__":
    main()
