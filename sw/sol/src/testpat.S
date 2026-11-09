; testpat.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
;
; A test picture for step 2, drawn into fb, to show that the pixel order and the line addresses are right:
;
;   +--------------------------------------+   a 1-pixel black border around the edge
;   |  ####    ####         \              |
;   |      ####    ####      \             |   top left: a checkerboard of 8 x 8 squares (64 x 64)
;   |  ####    ####           \            |   top right: a diagonal line (bit order: reversed
;   |      ####    ####        \           |      bits turn it into a saw-tooth)
;   |                                      |
;   |   +----+     +----+     +----+       |   below: three card outlines, 40 x 56, with cut corners,
;   |   |    |     |    |     |    |       |      at x = 8, 52 and 96 (52 and 96 aren't on a byte
;   |   +----+     +----+     +----+       |      boundary, so they test bits within a byte)
;   +--------------------------------------+
;
; fb: 168 lines of 18 bytes; bit 0 of a byte is its leftmost pixel; 1 = white, 0 = black.
#include <msp430.h>
#include "sol.h"

#define PAT_CARD_W  40
#define PAT_CARD_H  56
#define CARD_Y  88

        .text

; test_pattern: draws the test picture into fb and marks every line dirty. Call lcd_flush to show it.
;   in:      none
;   out:     none
;   changes: R11-R15
        .global test_pattern
test_pattern:
        ; start from all white
        mov.w   #fb, R14
        mov.w   #LCD_H*LINE/2, R15                      ; 1512 words
1:      mov.w   #0xFFFF, 0(R14)
        incd.w  R14
        dec.w   R15
        jnz     1b

        ; border: top and bottom lines, left and right columns
        clr.w   R12
        clr.w   R13
        mov.w   #LCD_W, R11
        call    #hline                                  ; top: (0,0) to (143,0)
        clr.w   R12
        mov.w   #LCD_H-1, R13
        mov.w   #LCD_W, R11
        call    #hline                                  ; bottom: (0,167) to (143,167)
        clr.w   R12
        clr.w   R13
        mov.w   #LCD_H, R11
        call    #vline                                  ; left: (0,0) to (0,167)
        mov.w   #LCD_W-1, R12
        clr.w   R13
        mov.w   #LCD_H, R11
        call    #vline                                  ; right: (143,0) to (143,167)

        ; checkerboard: lines 8-71, bytes 1-8 (x = 8-71); each square is one byte wide and 8 lines tall
        mov.w   #8, R13                                 ; R13 = y
chk_line:
        mov.w   R13, R14
        rlam.w  #4, R14                                 ; y * 16
        add.w   R13, R14
        add.w   R13, R14                                ; y * 18: the line's first byte
        inc.w   R14                                     ; byte 1
        mov.w   R13, R15
        sub.w   #8, R15
        rrum.w  #3, R15                                 ; R15 = the square's row, 0-7
        mov.w   #8, R11                                 ; 8 squares across
chk_byte:
        bit.w   #1, R15                                 ; row + column odd: black
        jz      1f
        clr.b   fb(R14)
1:      inc.w   R14
        inc.w   R15                                     ; next column flips the colour
        dec.w   R11
        jnz     chk_byte
        inc.w   R13
        cmp.w   #8+64, R13
        jne     chk_line

        ; diagonal: (80,8) to (135,63), one pixel per line
        mov.w   #80, R12
        mov.w   #8, R13
        mov.w   #56, R11
1:      call    #px_black
        inc.w   R12
        inc.w   R13
        dec.w   R11
        jnz     1b

        ; three cards
        mov.w   #8, R12
        mov.w   #CARD_Y, R13
        call    #card
        mov.w   #52, R12
        mov.w   #CARD_Y, R13
        call    #card
        mov.w   #96, R12
        mov.w   #CARD_Y, R13
        call    #card

        ; mark lines 0-167 dirty: 21 bytes of ones (10 words and a byte); the 22nd byte is padding
        mov.w   #dirty, R14
        mov.w   #10, R15
1:      mov.w   #0xFFFF, 0(R14)
        incd.w  R14
        dec.w   R15
        jnz     1b
        mov.b   #0xFF, 0(R14)                           ; byte 20: lines 160-167
        clr.b   1(R14)                                  ; byte 21: no lines
        ret

; card: draws a card outline, PAT_CARD_W x PAT_CARD_H, with its corner pixels left out so it looks rounded.
;   in:      R12 = left x, R13 = top y
;   out:     none
;   changes: R11-R15
card:
        push.w  R9
        push.w  R10
        mov.w   R12, R9                                 ; R9 = x
        mov.w   R13, R10                                ; R10 = y
        mov.w   R9, R12
        inc.w   R12
        mov.w   R10, R13
        mov.w   #PAT_CARD_W-2, R11
        call    #hline                                  ; top
        mov.w   R9, R12
        inc.w   R12
        mov.w   R10, R13
        add.w   #PAT_CARD_H-1, R13
        mov.w   #PAT_CARD_W-2, R11
        call    #hline                                  ; bottom
        mov.w   R9, R12
        mov.w   R10, R13
        inc.w   R13
        mov.w   #PAT_CARD_H-2, R11
        call    #vline                                  ; left
        mov.w   R9, R12
        add.w   #PAT_CARD_W-1, R12
        mov.w   R10, R13
        inc.w   R13
        mov.w   #PAT_CARD_H-2, R11
        call    #vline                                  ; right
        pop.w   R10
        pop.w   R9
        ret

; hline: draws a black horizontal line, left to right.
;   in:      R12 = x, R13 = y, R11 = length in pixels (at least 1)
;   out:     none
;   changes: R11, R12, R14, R15
hline:
        call    #px_black
        inc.w   R12
        dec.w   R11
        jnz     hline
        ret

; vline: draws a black vertical line, top to bottom.
;   in:      R12 = x, R13 = y, R11 = length in pixels (at least 1)
;   out:     none
;   changes: R11, R13, R14, R15
vline:
        call    #px_black
        inc.w   R13
        dec.w   R11
        jnz     vline
        ret

; px_black: makes one pixel black. Doesn't mark its line dirty.
;   in:      R12 = x (0-143), R13 = y (0-167)
;   out:     none
;   changes: R14, R15
px_black:
        mov.w   R13, R14
        rlam.w  #4, R14                                 ; y * 16
        add.w   R13, R14
        add.w   R13, R14                                ; y * 18
        mov.w   R12, R15
        rrum.w  #3, R15                                 ; x / 8: the byte in the line
        add.w   R15, R14                                ; R14 = the pixel's byte in fb
        mov.w   R12, R15
        and.w   #7, R15                                 ; x % 8: the bit in the byte
        mov.b   bit_mask(R15), R15
        bic.b   R15, fb(R14)                            ; 0 = black
        ret

        .section .rodata
bit_mask:
        .byte   BIT0, BIT1, BIT2, BIT3, BIT4, BIT5, BIT6, BIT7
