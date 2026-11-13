; font.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
;
; The glyphs, as constants in FRAM: a 5 x 7 font, the card ranks, and the suits in two sizes. Drawn by gfx.S.
;
; A glyph is: .byte width, height, then one row per line, top first. A row is a byte for glyphs up to 8 pixels
; wide and a word for wider ones (up to 16); bit 0 is the leftmost pixel and 1 is ink (black). Each glyph starts
; on an even address, so word rows are aligned.
;
; Rows are written as pixel art with the row macro: # is ink, . is paper. "row .###." assembles to .byte 0x0E.
#include <msp430.h>
#include "sol.h"

; row ART: one row of a glyph, from pixel art (# ink, . paper), as a byte (up to 8 pixels) or a word (9-16)
        .macro  row art
        .set    _bits, 0
        .set    _bit, 1
        .irpc   c, \art
        .ifc    \c, #
        .set    _bits, _bits | _bit
        .endif
        .set    _bit, _bit << 1
        .endr
        .if     _bit > 0x100
        .word   _bits
        .else
        .byte   _bits
        .endif
        .endm

        .section .rodata

; font_table: the glyph for each character from ' ' (0x20) to '_' (0x5F); gfx_text maps a-z to A-Z first.
; Characters without a glyph show as '?'.
        .balign 2
        .global font_table
font_table:
        .word   f_space, f_excl, f_qm, f_qm, f_qm, f_pct, f_qm, f_apos         ;   ! " # $ % & '
        .word   f_lpar, f_rpar, f_qm, f_plus, f_comma, f_minus, f_dot, f_slash ; ( ) * + , - . /
        .word   f_0, f_1, f_2, f_3, f_4, f_5, f_6, f_7                         ; 0-7
        .word   f_8, f_9, f_colon, f_qm, f_qm, f_equal, f_qm, f_qm             ; 8 9 : ; < = > ?
        .word   f_qm, f_A, f_B, f_C, f_D, f_E, f_F, f_G                        ; @ A-G
        .word   f_H, f_I, f_J, f_K, f_L, f_M, f_N, f_O                         ; H-O
        .word   f_P, f_Q, f_R, f_S, f_T, f_U, f_V, f_W                         ; P-W
        .word   f_X, f_Y, f_Z, f_qm, f_qm, f_qm, f_qm, f_qm                    ; X Y Z [ \ ] ^ _

; rank_glyphs: the glyph for each rank, 1 (ace) to 13 (king); entry 0 is unused
        .global rank_glyphs
rank_glyphs:
        .word   f_qm, f_A, f_2, f_3, f_4, f_5, f_6, f_7, f_8, f_9, r_10, f_J, f_Q, f_K

; small_suits, big_suits: the suit glyphs by suit number (0 spades, 1 clubs, 2 hearts, 3 diamonds). Black suits
; are solid, red ones outlined, as the display has no colour.
        .global small_suits, big_suits
small_suits:
        .word   s_spade, s_club, s_heart, s_diamond
big_suits:
        .word   b_spade, b_club, b_heart, b_diamond

; ---- ranks ----

; 10 is narrower than two font digits, to fit a card's corner: 7 pixels
        .balign 2
r_10:   .byte   7, 7
        row     .#..##.
        row     ##.#..#
        row     .#.#..#
        row     .#.#..#
        row     .#.#..#
        row     .#.#..#
        row     .#..##.

; ---- small suits, 5 x 7, beside the rank ----

        .balign 2
s_spade: .byte  5, 7
        row     ..#..
        row     ..#..
        row     .###.
        row     #####
        row     #####
        row     ..#..
        row     .###.

        .balign 2
s_club: .byte   5, 7
        row     .###.
        row     .###.
        row     ##.##
        row     #####
        row     ##.##
        row     ..#..
        row     .###.

        .balign 2
s_heart: .byte  5, 7
        row     .#.#.
        row     #.#.#
        row     #...#
        row     #...#
        row     .#.#.
        row     ..#..
        row     .....

        .balign 2
s_diamond: .byte 5, 7
        row     ..#..
        row     .#.#.
        row     .#.#.
        row     #...#
        row     .#.#.
        row     .#.#.
        row     ..#..

; ---- big suits, 9 wide, in the middle of a whole card ----

        .balign 2
b_spade: .byte  9, 9
        row     ....#....
        row     ...###...
        row     ..#####..
        row     .#######.
        row     #########
        row     #########
        row     .##.#.##.
        row     ....#....
        row     ...###...

        .balign 2
b_club: .byte   9, 9
        row     ...###...
        row     ..#####..
        row     ..#####..
        row     ##.###.##
        row     #########
        row     #########
        row     ##..#..##
        row     ....#....
        row     ...###...

        .balign 2
b_heart: .byte  9, 8
        row     .##...##.
        row     #..#.#..#
        row     #...#...#
        row     #.......#
        row     .#.....#.
        row     ..#...#..
        row     ...#.#...
        row     ....#....

        .balign 2
b_diamond: .byte 9, 9
        row     ....#....
        row     ...#.#...
        row     ..#...#..
        row     .#.....#.
        row     #.......#
        row     .#.....#.
        row     ..#...#..
        row     ...#.#...
        row     ....#....

; ---- the font: 5 x 7, drawn 6 pixels apart ----

        .balign 2
f_space: .byte  5, 0            ; no rows: only moves on

        .balign 2
f_excl: .byte   5, 7
        row     ..#..
        row     ..#..
        row     ..#..
        row     ..#..
        row     ..#..
        row     .....
        row     ..#..

        .balign 2
f_pct:  .byte   5, 7
        row     ##...
        row     ##..#
        row     ...#.
        row     ..#..
        row     .#...
        row     #..##
        row     ...##

        .balign 2
f_apos: .byte   5, 7
        row     ..#..
        row     ..#..
        row     .#...
        row     .....
        row     .....
        row     .....
        row     .....

        .balign 2
f_lpar: .byte   5, 7
        row     ...#.
        row     ..#..
        row     .#...
        row     .#...
        row     .#...
        row     ..#..
        row     ...#.

        .balign 2
f_rpar: .byte   5, 7
        row     .#...
        row     ..#..
        row     ...#.
        row     ...#.
        row     ...#.
        row     ..#..
        row     .#...

        .balign 2
f_plus: .byte   5, 7
        row     .....
        row     ..#..
        row     ..#..
        row     #####
        row     ..#..
        row     ..#..
        row     .....

        .balign 2
f_comma: .byte  5, 7
        row     .....
        row     .....
        row     .....
        row     .....
        row     .##..
        row     ..#..
        row     .#...

        .balign 2
f_minus: .byte  5, 7
        row     .....
        row     .....
        row     .....
        row     #####
        row     .....
        row     .....
        row     .....

        .balign 2
f_dot:  .byte   5, 7
        row     .....
        row     .....
        row     .....
        row     .....
        row     .....
        row     .##..
        row     .##..

        .balign 2
f_slash: .byte  5, 7
        row     .....
        row     ....#
        row     ...#.
        row     ..#..
        row     .#...
        row     #....
        row     .....

        .balign 2
f_0:    .byte   5, 7
        row     .###.
        row     #...#
        row     #..##
        row     #.#.#
        row     ##..#
        row     #...#
        row     .###.

        .balign 2
f_1:    .byte   5, 7
        row     ..#..
        row     .##..
        row     ..#..
        row     ..#..
        row     ..#..
        row     ..#..
        row     .###.

        .balign 2
f_2:    .byte   5, 7
        row     .###.
        row     #...#
        row     ....#
        row     ...#.
        row     ..#..
        row     .#...
        row     #####

        .balign 2
f_3:    .byte   5, 7
        row     #####
        row     ...#.
        row     ..#..
        row     ...#.
        row     ....#
        row     #...#
        row     .###.

        .balign 2
f_4:    .byte   5, 7
        row     ...#.
        row     ..##.
        row     .#.#.
        row     #..#.
        row     #####
        row     ...#.
        row     ...#.

        .balign 2
f_5:    .byte   5, 7
        row     #####
        row     #....
        row     ####.
        row     ....#
        row     ....#
        row     #...#
        row     .###.

        .balign 2
f_6:    .byte   5, 7
        row     ..##.
        row     .#...
        row     #....
        row     ####.
        row     #...#
        row     #...#
        row     .###.

        .balign 2
f_7:    .byte   5, 7
        row     #####
        row     ....#
        row     ...#.
        row     ..#..
        row     .#...
        row     .#...
        row     .#...

        .balign 2
f_8:    .byte   5, 7
        row     .###.
        row     #...#
        row     #...#
        row     .###.
        row     #...#
        row     #...#
        row     .###.

        .balign 2
f_9:    .byte   5, 7
        row     .###.
        row     #...#
        row     #...#
        row     .####
        row     ....#
        row     ...#.
        row     .##..

        .balign 2
f_colon: .byte  5, 7
        row     .....
        row     .##..
        row     .##..
        row     .....
        row     .##..
        row     .##..
        row     .....

        .balign 2
f_equal: .byte  5, 7
        row     .....
        row     .....
        row     #####
        row     .....
        row     #####
        row     .....
        row     .....

        .balign 2
f_qm:   .byte   5, 7
        row     .###.
        row     #...#
        row     ....#
        row     ...#.
        row     ..#..
        row     .....
        row     ..#..

        .balign 2
f_A:    .byte   5, 7
        row     .###.
        row     #...#
        row     #...#
        row     #####
        row     #...#
        row     #...#
        row     #...#

        .balign 2
f_B:    .byte   5, 7
        row     ####.
        row     #...#
        row     #...#
        row     ####.
        row     #...#
        row     #...#
        row     ####.

        .balign 2
f_C:    .byte   5, 7
        row     .###.
        row     #...#
        row     #....
        row     #....
        row     #....
        row     #...#
        row     .###.

        .balign 2
f_D:    .byte   5, 7
        row     ###..
        row     #..#.
        row     #...#
        row     #...#
        row     #...#
        row     #..#.
        row     ###..

        .balign 2
f_E:    .byte   5, 7
        row     #####
        row     #....
        row     #....
        row     ####.
        row     #....
        row     #....
        row     #####

        .balign 2
f_F:    .byte   5, 7
        row     #####
        row     #....
        row     #....
        row     ####.
        row     #....
        row     #....
        row     #....

        .balign 2
f_G:    .byte   5, 7
        row     .###.
        row     #...#
        row     #....
        row     #.###
        row     #...#
        row     #...#
        row     .####

        .balign 2
f_H:    .byte   5, 7
        row     #...#
        row     #...#
        row     #...#
        row     #####
        row     #...#
        row     #...#
        row     #...#

        .balign 2
f_I:    .byte   5, 7
        row     .###.
        row     ..#..
        row     ..#..
        row     ..#..
        row     ..#..
        row     ..#..
        row     .###.

        .balign 2
f_J:    .byte   5, 7
        row     ..###
        row     ...#.
        row     ...#.
        row     ...#.
        row     ...#.
        row     #..#.
        row     .##..

        .balign 2
f_K:    .byte   5, 7
        row     #...#
        row     #..#.
        row     #.#..
        row     ##...
        row     #.#..
        row     #..#.
        row     #...#

        .balign 2
f_L:    .byte   5, 7
        row     #....
        row     #....
        row     #....
        row     #....
        row     #....
        row     #....
        row     #####

        .balign 2
f_M:    .byte   5, 7
        row     #...#
        row     ##.##
        row     #.#.#
        row     #.#.#
        row     #...#
        row     #...#
        row     #...#

        .balign 2
f_N:    .byte   5, 7
        row     #...#
        row     #...#
        row     ##..#
        row     #.#.#
        row     #..##
        row     #...#
        row     #...#

        .balign 2
f_O:    .byte   5, 7
        row     .###.
        row     #...#
        row     #...#
        row     #...#
        row     #...#
        row     #...#
        row     .###.

        .balign 2
f_P:    .byte   5, 7
        row     ####.
        row     #...#
        row     #...#
        row     ####.
        row     #....
        row     #....
        row     #....

        .balign 2
f_Q:    .byte   5, 7
        row     .###.
        row     #...#
        row     #...#
        row     #...#
        row     #.#.#
        row     #..#.
        row     .##.#

        .balign 2
f_R:    .byte   5, 7
        row     ####.
        row     #...#
        row     #...#
        row     ####.
        row     #.#..
        row     #..#.
        row     #...#

        .balign 2
f_S:    .byte   5, 7
        row     .####
        row     #....
        row     #....
        row     .###.
        row     ....#
        row     ....#
        row     ####.

        .balign 2
f_T:    .byte   5, 7
        row     #####
        row     ..#..
        row     ..#..
        row     ..#..
        row     ..#..
        row     ..#..
        row     ..#..

        .balign 2
f_U:    .byte   5, 7
        row     #...#
        row     #...#
        row     #...#
        row     #...#
        row     #...#
        row     #...#
        row     .###.

        .balign 2
f_V:    .byte   5, 7
        row     #...#
        row     #...#
        row     #...#
        row     #...#
        row     #...#
        row     .#.#.
        row     ..#..

        .balign 2
f_W:    .byte   5, 7
        row     #...#
        row     #...#
        row     #...#
        row     #.#.#
        row     #.#.#
        row     #.#.#
        row     .#.#.

        .balign 2
f_X:    .byte   5, 7
        row     #...#
        row     #...#
        row     .#.#.
        row     ..#..
        row     .#.#.
        row     #...#
        row     #...#

        .balign 2
f_Y:    .byte   5, 7
        row     #...#
        row     #...#
        row     .#.#.
        row     ..#..
        row     ..#..
        row     ..#..
        row     ..#..

        .balign 2
f_Z:    .byte   5, 7
        row     #####
        row     ....#
        row     ...#.
        row     ..#..
        row     .#...
        row     #....
        row     #####

; ---- the small font: 3 x 5, drawn 4 pixels apart (gfx_text_small), for labels and small numbers ----

; small_table: the small glyph for each character from ' ' (0x20) to '_' (0x5F), like font_table. Only digits,
; capitals, space and '-' have glyphs; anything else shows as '?'.
        .balign 2
        .global small_table
small_table:
        .word   s_space, s_qm, s_qm, s_qm, s_qm, s_qm, s_qm, s_qm              ;  !"#$%&'
        .word   s_qm, s_qm, s_qm, s_qm, s_qm, s_minus, s_qm, s_qm              ; ()*+,-./
        .word   s_0, s_1, s_2, s_3, s_4, s_5, s_6, s_7                         ; 01234567
        .word   s_8, s_9, s_qm, s_qm, s_qm, s_qm, s_qm, s_qm                   ; 89:;<=>?
        .word   s_qm, s_A, s_B, s_C, s_D, s_E, s_F, s_G                        ; @ABCDEFG
        .word   s_H, s_I, s_J, s_K, s_L, s_M, s_N, s_O                         ; HIJKLMNO
        .word   s_P, s_Q, s_R, s_S, s_T, s_U, s_V, s_W                         ; PQRSTUVW
        .word   s_X, s_Y, s_Z, s_qm, s_qm, s_qm, s_qm, s_qm                    ; XYZ[\]^_

        .balign 2
s_space: .byte 3, 0                     ; no rows: only moves on

        .balign 2
s_minus:.byte   3, 5
        row     ...
        row     ...
        row     ###
        row     ...
        row     ...

        .balign 2
s_qm:   .byte   3, 5
        row     ###
        row     ..#
        row     .#.
        row     ...
        row     .#.

        .balign 2
s_0:    .byte   3, 5
        row     ###
        row     #.#
        row     #.#
        row     #.#
        row     ###

        .balign 2
s_1:    .byte   3, 5
        row     .#.
        row     ##.
        row     .#.
        row     .#.
        row     ###

        .balign 2
s_2:    .byte   3, 5
        row     ###
        row     ..#
        row     ###
        row     #..
        row     ###

        .balign 2
s_3:    .byte   3, 5
        row     ###
        row     ..#
        row     .##
        row     ..#
        row     ###

        .balign 2
s_4:    .byte   3, 5
        row     #.#
        row     #.#
        row     ###
        row     ..#
        row     ..#

        .balign 2
s_5:    .byte   3, 5
        row     ###
        row     #..
        row     ###
        row     ..#
        row     ###

        .balign 2
s_6:    .byte   3, 5
        row     ###
        row     #..
        row     ###
        row     #.#
        row     ###

        .balign 2
s_7:    .byte   3, 5
        row     ###
        row     ..#
        row     .#.
        row     .#.
        row     .#.

        .balign 2
s_8:    .byte   3, 5
        row     ###
        row     #.#
        row     ###
        row     #.#
        row     ###

        .balign 2
s_9:    .byte   3, 5
        row     ###
        row     #.#
        row     ###
        row     ..#
        row     ###

        .balign 2
s_A:    .byte   3, 5
        row     .#.
        row     #.#
        row     ###
        row     #.#
        row     #.#

        .balign 2
s_B:    .byte   3, 5
        row     ##.
        row     #.#
        row     ##.
        row     #.#
        row     ##.

        .balign 2
s_C:    .byte   3, 5
        row     .##
        row     #..
        row     #..
        row     #..
        row     .##

        .balign 2
s_D:    .byte   3, 5
        row     ##.
        row     #.#
        row     #.#
        row     #.#
        row     ##.

        .balign 2
s_E:    .byte   3, 5
        row     ###
        row     #..
        row     ##.
        row     #..
        row     ###

        .balign 2
s_F:    .byte   3, 5
        row     ###
        row     #..
        row     ##.
        row     #..
        row     #..

        .balign 2
s_G:    .byte   3, 5
        row     .##
        row     #..
        row     #.#
        row     #.#
        row     .##

        .balign 2
s_H:    .byte   3, 5
        row     #.#
        row     #.#
        row     ###
        row     #.#
        row     #.#

        .balign 2
s_I:    .byte   3, 5
        row     ###
        row     .#.
        row     .#.
        row     .#.
        row     ###

        .balign 2
s_J:    .byte   3, 5
        row     ..#
        row     ..#
        row     ..#
        row     #.#
        row     .#.

        .balign 2
s_K:    .byte   3, 5
        row     #.#
        row     #.#
        row     ##.
        row     #.#
        row     #.#

        .balign 2
s_L:    .byte   3, 5
        row     #..
        row     #..
        row     #..
        row     #..
        row     ###

        .balign 2
s_M:    .byte   3, 5
        row     #.#
        row     ###
        row     #.#
        row     #.#
        row     #.#

        .balign 2
s_N:    .byte   3, 5
        row     ##.
        row     #.#
        row     #.#
        row     #.#
        row     #.#

        .balign 2
s_O:    .byte   3, 5
        row     .#.
        row     #.#
        row     #.#
        row     #.#
        row     .#.

        .balign 2
s_P:    .byte   3, 5
        row     ##.
        row     #.#
        row     ##.
        row     #..
        row     #..

        .balign 2
s_Q:    .byte   3, 5
        row     .#.
        row     #.#
        row     #.#
        row     ###
        row     .##

        .balign 2
s_R:    .byte   3, 5
        row     ##.
        row     #.#
        row     ##.
        row     #.#
        row     #.#

        .balign 2
s_S:    .byte   3, 5
        row     .##
        row     #..
        row     .#.
        row     ..#
        row     ##.

        .balign 2
s_T:    .byte   3, 5
        row     ###
        row     .#.
        row     .#.
        row     .#.
        row     .#.

        .balign 2
s_U:    .byte   3, 5
        row     #.#
        row     #.#
        row     #.#
        row     #.#
        row     ###

        .balign 2
s_V:    .byte   3, 5
        row     #.#
        row     #.#
        row     #.#
        row     #.#
        row     .#.

        .balign 2
s_W:    .byte   3, 5
        row     #.#
        row     #.#
        row     #.#
        row     ###
        row     #.#

        .balign 2
s_X:    .byte   3, 5
        row     #.#
        row     #.#
        row     .#.
        row     #.#
        row     #.#

        .balign 2
s_Y:    .byte   3, 5
        row     #.#
        row     #.#
        row     .#.
        row     .#.
        row     .#.

        .balign 2
s_Z:    .byte   3, 5
        row     ###
        row     ..#
        row     .#.
        row     #..
        row     ###
