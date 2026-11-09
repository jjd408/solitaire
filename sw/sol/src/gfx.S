; gfx.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
;
; Drawing into the framebuffer (fb, in lcd.S). Every routine marks the lines it changes in dirty, so lcd_flush
; sends exactly those. Nothing here touches the display itself.
;
; Coordinates are pixels: x 0-143 left to right, y 0-167 top to bottom. Nothing is drawn at or below clip_bottom
; (normally 168): gfx_card lowers it to draw only the visible top part of a card that others overlap.
#include <msp430.h>
#include "sol.h"

#define OP_BLACK   0
#define OP_WHITE   1
#define OP_INVERT  2
#define OP_CHECKER 3            /* a 50% checkerboard, fixed to the screen */

        .section .data
        .balign 2
clip_bottom:
        .word   LCD_H           ; first line not drawn

        .text

; gfx_clear: makes the whole screen white and marks every line dirty.
;   in:      none
;   out:     none
;   changes: R12, R13
        .global gfx_clear
gfx_clear:
        mov.w   #fb, R12
        mov.w   #LCD_H*LINE/2, R13                      ; 1512 words
1:      mov.w   #0xFFFF, 0(R12)
        incd.w  R12
        dec.w   R13
        jnz     1b
        mov.w   #dirty, R12                             ; lines 0-167: 21 bytes of ones (10 words and a byte)
        mov.w   #10, R13
2:      mov.w   #0xFFFF, 0(R12)
        incd.w  R12
        dec.w   R13
        jnz     2b
        mov.b   #0xFF, 0(R12)
        ret

; gfx_mark: marks lines dirty.
;   in:      R12 = first line, R13 = number of lines (0 does nothing)
;   out:     none
;   changes: R12-R15
        .global gfx_mark
gfx_mark:
        tst.w   R13
        jz      2f
1:      mov.w   R12, R14
        rrum.w  #3, R14                                 ; the line's byte in dirty
        mov.w   R12, R15
        and.w   #7, R15
        mov.b   bit_mask(R15), R15                      ; and its bit
        bis.b   R15, dirty(R14)
        inc.w   R12
        dec.w   R13
        jnz     1b
2:      ret

; gfx_black, gfx_white, gfx_invert, gfx_checker: fill a rectangle with black, white, the inverse of what's there,
; or a 50% checkerboard (for card backs and dotted outlines).
;   in:      R12 = x, R13 = y, R14 = width, R15 = height (in pixels; 0 draws nothing)
;   out:     none
;   changes: R11-R15
        .global gfx_black, gfx_white, gfx_invert, gfx_checker
gfx_black:
        mov.w   #OP_BLACK, R11
        jmp     rect
gfx_white:
        mov.w   #OP_WHITE, R11
        jmp     rect
gfx_invert:
        mov.w   #OP_INVERT, R11
        jmp     rect
gfx_checker:
        mov.w   #OP_CHECKER, R11
        ; fall into rect

; rect: does the work for the four above, with R11 = what to do. Each line of the rectangle is a run of bytes in
; fb: a first byte with a mask of the pixels from x on, whole bytes, and a last byte with a mask of the pixels up
; to the right edge (one byte with both masks when it's all in one).
;   R4 = the first byte on this line, R5 = lines left, R6 = first byte's mask, R7 = last byte's mask,
;   R8 = bytes from the first to the last, R9 = y of this line
rect:
        pushm.w #6, R9                                  ; R4-R9
        tst.w   R14
        jz      rect_done
        mov.w   &clip_bottom, R4                        ; clip: lines y to clip_bottom - 1 can be drawn
        sub.w   R13, R4
        cmp.w   #1, R4
        jl      rect_done                               ; none
        cmp.w   R15, R4
        jge     1f
        mov.w   R4, R15                                 ; fewer than asked
1:      tst.w   R15
        jz      rect_done
        mov.w   R13, R9                                 ; R9 = y
        mov.w   R15, R5                                 ; R5 = lines
        mov.w   R12, R6                                 ; x and width, before gfx_mark changes R12-R15
        mov.w   R14, R7
        mov.w   R13, R12
        mov.w   R5, R13
        call    #gfx_mark
        mov.w   R9, R4                                  ; R4 = fb + y * 18 + x / 8
        rlam.w  #4, R4
        add.w   R9, R4
        add.w   R9, R4
        add.w   #fb, R4
        mov.w   R6, R12
        rrum.w  #3, R12                                 ; R12 = x / 8, the first byte in the line
        add.w   R12, R4
        mov.w   R6, R13                                 ; R13 = x + width - 1, the last pixel
        add.w   R7, R13
        dec.w   R13
        mov.w   R13, R8
        rrum.w  #3, R8
        sub.w   R12, R8                                 ; R8 = last byte - first byte
        and.w   #7, R6
        mov.b   left_mask(R6), R6                       ; pixels x % 8 to 7 of the first byte
        and.w   #7, R13
        mov.b   right_mask(R13), R7                     ; pixels 0 to (x + width - 1) % 8 of the last
        tst.w   R8
        jnz     rect_line
        and.w   R7, R6                                  ; all in one byte: both masks
rect_line:
        mov.w   R4, R12
        mov.w   R6, R13
        call    #apply                                  ; the first byte
        tst.w   R8
        jz      rect_next
        mov.w   R8, R14
        dec.w   R14                                     ; R14 = whole bytes between
        jz      3f
2:      inc.w   R12
        mov.w   #0xFF, R13
        call    #apply
        dec.w   R14
        jnz     2b
3:      inc.w   R12
        mov.w   R7, R13
        call    #apply                                  ; the last byte
rect_next:
        add.w   #LINE, R4
        inc.w   R9
        dec.w   R5
        jnz     rect_line
rect_done:
        popm.w  #6, R9
        ret

; apply: does R11's operation to the pixels of one fb byte.
;   in:      R12 = the byte's address, R13 = mask of the pixels to change, R11 = operation, R9 = the line's y
;   out:     none
;   changes: R15
apply:
        cmp.w   #OP_WHITE, R11
        jhs     1f
        bic.b   R13, 0(R12)                             ; black: 0 is black
        ret
1:      jne     2f
        bis.b   R13, 0(R12)                             ; white
        ret
2:      cmp.w   #OP_INVERT, R11
        jne     3f
        xor.b   R13, 0(R12)
        ret
3:      bis.b   R13, 0(R12)                             ; checker: white, then black where x + y is even
        mov.b   #0x55, R15                              ; even line: pixels 0, 2, 4, 6
        bit.w   #1, R9
        jz      4f
        mov.b   #0xAA, R15                              ; odd line: 1, 3, 5, 7
4:      and.w   R13, R15
        bic.b   R15, 0(R12)
        ret

; gfx_glyph: draws a glyph (see font.S) in black, leaving its paper as it is.
;   in:      R12 = x, R13 = y (its top left), R14 = the glyph
;   out:     R12 = x + width + 1, where the next glyph of a line of text goes
;   changes: R11-R15
; A glyph that would run past the right edge isn't drawn. Each row is shifted to x's place in a byte and cleared
; out of three fb bytes (a row of up to 16 pixels, shifted by up to 7, spans at most 3).
;   R4 = fb byte for this row, R5 = rows left, R6 = width, R7 = shift (x % 8), R8 = the glyph's next row,
;   R9 = y
        .global gfx_glyph
gfx_glyph:
        pushm.w #6, R9
        mov.b   @R14+, R6                               ; R6 = width
        mov.b   @R14+, R5                               ; R5 = height
        mov.w   R14, R8                                 ; R8 = the rows
        mov.w   R12, R7                                 ; R7 = x
        mov.w   R13, R9                                 ; R9 = y
        mov.w   R12, R11
        add.w   R6, R11
        push.w  R11                                     ; x + width, for the result
        cmp.w   #LCD_W+1, R11
        jhs     glyph_done                              ; past the right edge
        mov.w   &clip_bottom, R4                        ; clip the rows
        sub.w   R9, R4
        cmp.w   #1, R4
        jl      glyph_done
        cmp.w   R5, R4
        jge     1f
        mov.w   R4, R5
1:      tst.w   R5
        jz      glyph_done                              ; no rows (a space)
        mov.w   R9, R12
        mov.w   R5, R13
        call    #gfx_mark
        mov.w   R9, R4                                  ; R4 = fb + y * 18 + x / 8
        rlam.w  #4, R4
        add.w   R9, R4
        add.w   R9, R4
        add.w   #fb, R4
        mov.w   R7, R12
        rrum.w  #3, R12
        add.w   R12, R4
        and.w   #7, R7                                  ; R7 = shift
glyph_row:
        cmp.w   #9, R6
        jhs     2f
        mov.b   @R8+, R12                               ; a row of up to 8 pixels
        jmp     3f
2:      mov.w   @R8+, R12                               ; a row of 9-16
3:      clr.w   R13                                     ; R13:R12 = the row, shifted into place
        mov.w   R7, R14
        tst.w   R14
        jz      5f
4:      rla.w   R12
        rlc.w   R13
        dec.w   R14
        jnz     4b
5:      bic.b   R12, 0(R4)                              ; ink: clear to black
        swpb    R12
        bic.b   R12, 1(R4)
        bic.b   R13, 2(R4)
        add.w   #LINE, R4
        dec.w   R5
        jnz     glyph_row
glyph_done:
        pop.w   R12
        inc.w   R12                                     ; one pixel apart
        popm.w  #6, R9
        ret

; gfx_text: draws a line of text in the 5 x 7 font, 6 pixels a character. Lower case is drawn as upper case;
; characters the font lacks as '?'. Text stops at the right edge.
;   in:      R12 = x, R13 = y (top), R14 = the text, ending in a 0 byte
;   out:     R12 = x after the last character
;   changes: R11-R15
        .global gfx_text
gfx_text:
        push.w  R10
        push.w  R9
        mov.w   R13, R9                                 ; R9 = y
        mov.w   R14, R10                                ; R10 = next character
text_char:
        mov.b   @R10+, R14
        tst.w   R14
        jz      text_done
        cmp.w   #'a', R14
        jlo     1f
        cmp.w   #'z'+1, R14
        jhs     1f
        sub.w   #'a'-'A', R14                           ; lower case to upper
1:      sub.w   #' ', R14                               ; the font starts at ' '
        cmp.w   #64, R14
        jlo     2f
        mov.w   #'?'-' ', R14                           ; outside the font
2:      rla.w   R14
        mov.w   font_table(R14), R14
        mov.w   R9, R13
        call    #gfx_glyph                              ; moves R12 on
        jmp     text_char
text_done:
        pop.w   R9
        pop.w   R10
        ret

; gfx_number: draws a number in decimal, without leading zeros.
;   in:      R12 = x, R13 = y (top), R14 = the number (0-65535)
;   out:     R12 = x after the last digit
;   changes: R11-R15
        .global gfx_number
gfx_number:
        push.w  R10
        push.w  R9
        push.w  R13                                     ; y, as R13 counts digits below
        sub.w   #6, SP                                  ; room for 5 digits and the 0 that ends them
        mov.w   SP, R15                                 ; R15 = where the next digit goes
        mov.w   #powers_of_10, R10
        clr.w   R9                                      ; R9 = 1 once a digit has been written
num_power:
        mov.w   @R10+, R11                              ; R11 = 10000, 1000, 100, 10, 1
        mov.b   #'0', R13
1:      cmp.w   R11, R14                                ; count how many times it goes
        jlo     2f
        sub.w   R11, R14
        inc.b   R13
        jmp     1b
2:      cmp.w   #1, R11
        jeq     3f                                      ; always write the units
        tst.w   R9
        jnz     3f
        cmp.b   #'0', R13
        jeq     4f                                      ; a leading zero: skip it
3:      mov.b   R13, 0(R15)
        inc.w   R15
        mov.w   #1, R9
4:      cmp.w   #1, R11
        jne     num_power
        clr.b   0(R15)
        mov.w   SP, R14
        mov.w   6(SP), R13                              ; y
        call    #gfx_text
        add.w   #8, SP                                  ; the digits and y
        pop.w   R9
        pop.w   R10
        ret

; gfx_card: draws a card, or the top part of one where the next card in a column covers the rest.
;   in:      R12 = x, R13 = y (top left), R14 = the card (FACE_UP set for a face, else its back is drawn;
;            SELECTED set to draw it inverted), R15 = how many lines of it show (CARD_H for all of it)
;   out:     none
;   changes: R11-R15
; A face has the rank and a small suit at the top left, inside the outline, and a big suit in the middle (seen
; only on a whole card). A back is the outline around a checkerboard.
        .global gfx_card
gfx_card:
        pushm.w #5, R10                                 ; R6-R10
        push.w  &clip_bottom
        mov.w   R12, R6                                 ; R6 = x
        mov.w   R13, R7                                 ; R7 = y
        mov.w   R14, R8                                 ; R8 = card
        add.w   R13, R15                                ; draw only down to y + lines
        cmp.w   &clip_bottom, R15
        jhs     1f
        mov.w   R15, &clip_bottom
1:      mov.w   R6, R12
        mov.w   R7, R13
        mov.w   #CARD_W, R14
        mov.w   #CARD_H, R15
        call    #gfx_white
        mov.w   #gfx_black, R10
        call    #outline
        bit.b   #FACE_UP, R8
        jz      card_back
        mov.b   R8, R14                                 ; rank, at (x + 2, y + 2)
        and.w   #RANK_MASK, R14
        rla.w   R14
        mov.w   rank_glyphs(R14), R14
        mov.w   R6, R12
        add.w   #2, R12
        mov.w   R7, R13
        add.w   #2, R13
        call    #gfx_glyph
        mov.b   R8, R9                                  ; R9 = suit * 2, to index the suit tables
        rrum.w  #3, R9
        and.w   #6, R9
        mov.w   small_suits(R9), R14                    ; small suit, at (x + 12, y + 2)
        mov.w   R6, R12
        add.w   #12, R12
        mov.w   R7, R13
        add.w   #2, R13
        call    #gfx_glyph
        mov.w   big_suits(R9), R14                      ; big suit, centred across at (x + 5, y + 13)
        mov.w   R6, R12
        add.w   #5, R12
        mov.w   R7, R13
        add.w   #13, R13
        call    #gfx_glyph
        jmp     card_selected
card_back:
        mov.w   R6, R12                                 ; checkerboard inside, a white line from the outline
        add.w   #2, R12
        mov.w   R7, R13
        add.w   #2, R13
        mov.w   #CARD_W-4, R14
        mov.w   #CARD_H-4, R15
        call    #gfx_checker
card_selected:
        bit.b   #SELECTED, R8
        jz      card_done
        mov.w   R6, R12
        mov.w   R7, R13
        mov.w   #CARD_W, R14
        mov.w   #CARD_H, R15
        call    #gfx_invert
card_done:
        pop.w   &clip_bottom
        popm.w  #5, R10
        ret

; gfx_slot: draws an empty place for a pile: a dotted outline the size of a card.
;   in:      R12 = x, R13 = y (top left)
;   out:     none
;   changes: R11-R15
        .global gfx_slot
gfx_slot:
        pushm.w #5, R10
        mov.w   R12, R6
        mov.w   R13, R7
        mov.w   #CARD_W, R14
        mov.w   #CARD_H, R15
        call    #gfx_white
        mov.w   #gfx_checker, R10
        call    #outline
        popm.w  #5, R10
        ret

; outline: draws a card's outline, with its corner pixels left out so the corners look rounded.
;   in:      R6 = x, R7 = y, R10 = the rectangle routine to draw it with (gfx_black, gfx_checker)
;   out:     none
;   changes: R11-R15
outline:
        mov.w   R6, R12                                 ; top
        inc.w   R12
        mov.w   R7, R13
        mov.w   #CARD_W-2, R14
        mov.w   #1, R15
        call    R10
        mov.w   R6, R12                                 ; bottom
        inc.w   R12
        mov.w   R7, R13
        add.w   #CARD_H-1, R13
        mov.w   #CARD_W-2, R14
        mov.w   #1, R15
        call    R10
        mov.w   R6, R12                                 ; left
        mov.w   R7, R13
        inc.w   R13
        mov.w   #1, R14
        mov.w   #CARD_H-2, R15
        call    R10
        mov.w   R6, R12                                 ; right
        add.w   #CARD_W-1, R12
        mov.w   R7, R13
        inc.w   R13
        mov.w   #1, R14
        mov.w   #CARD_H-2, R15
        call    R10
        ret

        .section .rodata
bit_mask:                                               ; bit n
        .byte   0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80
left_mask:                                              ; bits n to 7
        .byte   0xFF, 0xFE, 0xFC, 0xF8, 0xF0, 0xE0, 0xC0, 0x80
right_mask:                                             ; bits 0 to n
        .byte   0x01, 0x03, 0x07, 0x0F, 0x1F, 0x3F, 0x7F, 0xFF
        .balign 2
powers_of_10:
        .word   10000, 1000, 100, 10, 1
