# LS013B7DH03 Cycle of Operation

Notes on the operational cycle of the Sharp Memory LCD (LS013B7DH03, 128x128), summarized from
`sharp_ls013b7dh03_memory_lcd_datasheet.pdf` in this directory.

## Two independent things happen continuously

The display has two orthogonal jobs the firmware has to keep running at once:

1. **EXTCOMIN toggling** - a square wave (54-65 Hz per spec, so pick something like 60Hz) that
   must never stop for more than ~1 frame period while VDD is up. This is nothing to do with
   pixel content - it flips the VCOM polarity to prevent DC bias buildup in the liquid crystal
   (LCD panels degrade if held at a constant polarity too long). This is why the firmware plan
   uses a timer interrupt just to wiggle this pin - it runs independently of whatever else the
   CPU is doing.
2. **SPI data transactions** - driven by SCS/SCLK/SI, used only when the display content
   actually needs to change.

## Power-up sequence (datasheet Figure 6-1)

1. VDD/VDDA rise to 3.0V.
2. Pixel memory initialization - clear the internal per-pixel memory via either the All Clear
   command or a full-screen white write.
3. Wait >=30us (T3) - release time for the TCOM latch init.
4. Wait >=30us (T4) - TCOM polarity initialization relative to EXTCOMIN.
5. Enter normal operation: EXTCOMIN toggling begins, SCS/SI/SCLK become available for data
   updates.

Power-down is the mirror image (re-clear memory, wait out T6, drop VDD).

## The SPI command format

Every SCS-high transaction starts with a 3-bit mode header on SI:

- **M0** (mode flag): `H` = data update mode (write to memory), `L` = display mode (just keep
  showing what's already latched - used when only toggling EXTCOMIN over serial instead of the
  dedicated pin, i.e. EXTMODE="L").
- **M1**: don't-care, always ignored functionally.
- **M2** (all-clear flag): `H` = wipe the whole panel to white and ignore everything else in the
  frame.

Three transaction shapes follow that header:

- **Single-line update** (SS6-5-1): `M0 M1 M2` -> 8-bit gate-line address (one-hot-ish, from the
  address table in the datasheet, selects which of the 128 rows) -> 128 bits of pixel data
  (`L`=black, `H`=white) -> trailing dummy bits, then SCS drops.
- **Multi-line update** (SS6-5-2): same idea chained - address, 128 data bits, 8 dummy bits, next
  address, next 128 data bits... all under one SCS pulse. This is the efficient path since SCS
  doesn't need to be reselected per row.
- **All-clear** (SS6-5-4): just `M0=L, M2=H` plus dummy bits - no address or data needed, clears
  everything to white.

Internally each line write is two-stage: the 128 bits first land in a **shift/latch register** on
the panel (the "data write period"), then get committed into the **pixel's own 1-bit memory cell**
(the "data transfer period"). That per-pixel memory is the whole point of "Memory-in-Pixel" - once
a row is written, the LC keeps displaying it with no further CPU/SPI activity, refresh, or
DRAM-style periodic rewrite. SPI bandwidth is only spent on rows that actually changed (e.g.
redraw just the tableau column where a card moved), which is what makes this display so
power-frugal for a mostly-static card layout.

## Practical implication for firmware

Since only EXTCOMIN has a hard real-time deadline (must keep toggling), a natural structure is: a
timer ISR flips EXTCOMIN on a steady cadence, and the main loop only touches SCS/SI/SCLK when the
game state actually needs a redraw - issuing multi-line writes for just the rows that changed
rather than the whole 128x128 frame.
