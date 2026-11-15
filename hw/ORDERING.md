# Ordering the Solitaire boards

How to order 2 fully assembled boards from JLCPCB, and the parts that don't come from JLCPCB: the displays and
the battery holders. Prices and stock were looked up on 2026-11-14 from distributor listings captured at
different times, so check the live pages before buying.

## Checklist

1. **Get the displays first** (see Displays below): they're the scarce part. The boards take 1–2 weeks; the
   displays may take much longer.
2. Run `sh sol/make_fab.sh` (from `hw/`) to make sure the order files match the current design.
3. Order the boards from JLCPCB (below).
4. Order 2 battery holders.
5. While waiting: a programmer for the Spy-Bi-Wire header (an MSP430 LaunchPad's eZ-FET, or an MSP-FET), and
   `mspdebug` built, or TI's UniFlash.

## The boards: JLCPCB, 2 assembled

`sol/make_fab.sh` checks the board (DRC with schematic parity) and writes the order files to `sol/fab/`:

| File | What it is |
| --- | --- |
| `sol-gerbers.zip` | The board: Gerbers and drill files |
| `jlc-bom.csv` | The parts list in JLCPCB's format, every part with its LCSC number |
| `jlc-cpl.csv` | Where each part goes, in JLCPCB's format, from the board's bottom-left corner |
| `sol-assembly.pdf` | The board with every part's reference, for checking rotations and the finished boards |
| `sol-bom.csv`, `sol-cpl.csv` | The same parts list and placement in neutral formats, for any other board house |

On jlcpcb.com:

1. **Upload `sol-gerbers.zip`.** Board options: 2 layers, 1.6 mm thick, quantity **5** (JLCPCB's minimum),
   surface finish **ENIG** (flat gold pads for the fine-pitch parts). Leave the rest at the defaults.
2. **Turn on PCB Assembly:** Economic, top side, **quantity 2**. The other 3 boards come back bare.
3. **Upload `jlc-bom.csv` and `jlc-cpl.csv`.** Check that every part is matched and in stock. The two to watch
   are the **MCU (C2053375)** and the **display connector (C425133)**, which have been short. If one is out,
   use JLCPCB's global sourcing or pre-order it into your parts store; either adds days.
4. **Check every part's rotation in the 3D preview**, and rotate any that are wrong. JLCPCB's footprints don't
   always share KiCad's zero; the usual suspects are U1, U2, Q1, L1, DS1 and the switches. Compare pin 1 with
   the dots on U1 and U2, and DS1's chamfered corner on `sol-assembly.pdf`.
5. **J3, the programming header, is the only through-hole part.** If the Economic tier won't fit it, leave it off
   and solder it by hand (4 pins).
6. Check the total, which shows import duties if any, and order.

**Estimated cost:** about **$90–125** for 2 assembled boards (plus 3 bare), including shipping, before any import
duty: 5 bare boards ~$20–25, assembly setup ~$8, ~$3 for each kind of part not on JLCPCB's standard reels
(~$30–45 here), parts ~$12–18, shipping ~$15–25. For comparison, 5 assembled boards would be about $110–145.

### Parts substituted in the BOM

Each is the same as the specified part or better:

| Part | Specified | Ordered | Why |
| --- | --- | --- | --- |
| C2, 22 µF output capacitor | GRM187R60J226ME15 (TI's datasheet) | GRM188R60J226ME15D (C440187) | TI's number isn't sold; same value, voltage, X5R, 0603 |
| C5, C6, 0.1 µF | GRM188R71C104KA01 | GCJ188R71C104KA01D (C710619) | The original is obsolete; Murata's automotive twin, same spec |
| R3, 13.3 kΩ (regulator CFG3) | RC0603FR-0713K3L | RT0603FRE0713K3L (C863573) | Not stocked; Yageo thin film, 1%, ±50 ppm/°C (the regulator needs 1% and 200 ppm/°C or better) |
| U1, the MCU | MSP430FR2355TDBT | MSP430FR2355TDBTR (C2053375) | The same chip, on a reel |

## Displays: Sharp LS013B7DH05 (2 needed)

The display plugs into DS1 (the AYF531035 FPC connector) and isn't part of the JLCPCB order.

| Source | Price each | Availability (2026-11-14) |
| --- | --- | --- |
| Bare LS013B7DH05 from DigiKey, LCSC, Avnet or Future Electronics | about $7–16 | **Mostly out of stock, 28-week factory lead time.** DigiKey doesn't keep it in stock; some Avnet listings show a few hundred, but in large-quantity price tiers |
| Adafruit #3502, *SHARP Memory Display Breakout 1.3″ 168×144* | about $25 (DigiKey); £20–26 in the UK | A few in stock at some shops (The Pi Hut, SB Components, Switch Science); out at others |

**The Adafruit breakout is probably the practical way to get 2 now.** It's the same size and resolution of Sharp
memory display, mounted with a regulator and level shifter, so it's very likely the LS013B7DH05 itself. Before
buying, check on Adafruit's product page or photos:

- that the panel is the **LS013B7DH05**, and
- that its ribbon (FPC) **plugs into a latched connector** on the breakout, rather than being soldered.

If both hold, unlatch the ribbon and move the bare display onto the board's connector. Even unmodified, a breakout
is handy for trying the firmware's display code on real glass before the boards arrive.

**Fitting the display:** the ribbon goes straight into DS1 with the glass face up (see "Display connector and FPC
routing" in `README.md`); open the connector's latch, slide the ribbon fully in, close the latch. Then check how
far the ribbon went in: the layout assumes its end stops 2.63 mm past the connector's pad row, putting the glass's
bottom edge 11.0 mm above it. Measure it, as the case window depends on it.

## Battery holders (2 needed)

About **$2 each**: Adafruit #4194, a 2 × AA open holder, is $1.95.

The board has **two solder pads**, TP1 (+, marked +) and TP2 (−), not a socket, and the #4194 ends in a JST-PH
plug. Either cut the plug off and solder the red wire to + and the black to −, or buy any 2 × AA holder with bare
wire leads instead (similar price). Q1 protects the board if the cells go in backwards, but check the wires' polarity
anyway.

## Budget for 2 handhelds

| Item | Cost |
| --- | --- |
| 2 assembled boards (JLCPCB) | ~$90–125 |
| 2 displays | ~$15–30 bare, or ~$50 as two Adafruit breakouts |
| 2 battery holders | ~$4 |
| Shipping for the displays and holders | a few dollars per shop |
| **Total** | **about $110–180**, plus any import duty |

## Sources

Display:
[DigiKey: LS013B7DH05](https://www.digikey.com/product-detail/en/sharp-microelectronics/LS013B7DH05/LS013B7DH05-ND/5799456),
[DigiKey (China): LS013B7DH05](https://digikey.cn/en/products/detail/sharp-microelectronics/LS013B7DH05/5799456),
[Future Electronics: LS013B7DH05](https://www.futureelectronics.com/p/8066542),
[LCSC: LS013B7DH05](https://www.lcsc.com/product-image/C17500193.html),
[Avnet: LS013B7DH05](https://www.avnet.com/americas/product/sharp/ls013b7dh05/evolve-5324512/),
[electronicsdatasheets.com: distributor prices](https://www.electronicsdatasheets.com/manufacturers/sharp-devices-europe/parts/ls013b7dh05),
[Findchips: LS013B7DH05](https://www.findchips.com/search/LS013B7DH05),
[The Pi Hut: Adafruit #3502](https://thepihut.com/products/adafruit-sharp-memory-display-breakout-1-3-168x144-monochrome-ada3502),
[SB Components: Adafruit #3502](https://shop.sb-components.co.uk/products/adafruit-sharp-memory-display-breakout-1-3-168x144-monochrome),
[Pimoroni: Adafruit #3502](https://shop.pimoroni.com/products/adafruit-sharp-memory-display-breakout-1-3-168x144-monochrome),
[Switch Science: Adafruit #3502](https://www.switch-science.com/catalog/3350/),
[electronicspecifier.com: DigiKey listing for #3502](https://www.electronicspecifier.com/product-centre/distributors/digi-key/part/5ab31e268929e541ee400e0d).

Battery holder:
[Adafruit #4194](https://www.adafruit.com/product/4194).

JLCPCB pricing:
[PCB assembly price](https://jlcpcb.com/help/article/pcb-assembly-price),
[what the assembly price includes](https://jlcpcb.com/help/article/40-pcb-assembly-price),
[PCB prototype assembly](https://jlcpcb.com/solutions/pcb-prototype-assembly).

Parts (LCSC):
[MSP430FR2355TDBTR](https://www.lcsc.com/product-detail/C2053375.html),
[TPS63900DSKR](https://www.lcsc.com/product-image/C1518762.html),
[AYF531035](https://www.lcsc.com/product-detail/C425133.html),
[SKRPACE010](https://www.lcsc.com/product-detail/C139797.html),
[IRLML6401TRPBF](https://www.lcsc.com/product-detail/C3034.html),
[GRM188R60J226ME15D](https://www.lcsc.com/product-image/C440187.html),
[GCJ188R71C104KA01D](https://jlcpcb.com/partdetail/748891-GCJ188R71C104KA01D/C710619),
[RT0603FRE0713K3L](https://www.lcsc.com/product-detail/C863573.html).
