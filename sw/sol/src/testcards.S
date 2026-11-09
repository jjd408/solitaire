; testcards.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
;
; The test screen for step 3: every graphic gfx.S can draw, laid out as in the game.
;
;   top row (y 2):   a back, an empty slot, the ace of spades selected, the four kings
;   tableau (y 30):  all 52 cards in 7 columns, spades A-K, then clubs, hearts and diamonds; column n starts
;                    with n face-down strips of 3 lines, face-up cards show 10 lines and the last shows whole
;   text (y 140):    the whole font, and a number
#include <msp430.h>
#include "sol.h"

#define TOP_Y    2
#define TABLE_Y  30
#define COL_X(n) (2 + 20 * (n))
#define DOWN     3              /* lines of a face-down strip */
#define UP       10             /* lines of a face-up strip */

        .text

; card_sheet: draws the test screen into fb and marks it dirty. Call lcd_flush to show it.
;   in:      none
;   out:     none
;   changes: R11-R15
        .global card_sheet
card_sheet:
        pushm.w #7, R10                                 ; R4-R10
        call    #gfx_clear

        ; top row
        mov.w   #COL_X(0), R12
        mov.w   #TOP_Y, R13
        clr.w   R14                                     ; face down
        mov.w   #CARD_H, R15
        call    #gfx_card
        mov.w   #COL_X(1), R12
        mov.w   #TOP_Y, R13
        call    #gfx_slot
        mov.w   #COL_X(2), R12
        mov.w   #TOP_Y, R13
        mov.w   #FACE_UP|SELECTED|SPADES|1, R14
        mov.w   #CARD_H, R15
        call    #gfx_card
        mov.w   #COL_X(3), R4                           ; the kings: R4 = x, R5 = card
        mov.w   #FACE_UP|SPADES|13, R5
1:      mov.w   R4, R12
        mov.w   #TOP_Y, R13
        mov.w   R5, R14
        mov.w   #CARD_H, R15
        call    #gfx_card
        add.w   #20, R4
        add.w   #0x10, R5                               ; next suit
        cmp.w   #COL_X(7), R4
        jne     1b

        ; tableau: R10 = the next card, 0-51; R9 = column; R8 = x; R7 = y; R6 = cards left in the column
        clr.w   R10
        clr.w   R9
sheet_column:
        mov.w   R9, R8                                  ; x = 2 + 20 * column
        rlam.w  #2, R8
        mov.w   R8, R12
        rlam.w  #2, R12
        add.w   R12, R8
        add.w   #2, R8
        mov.w   #TABLE_Y, R7
        mov.w   R9, R6                                  ; column n: n face-down strips
        tst.w   R6
        jz      2f
1:      mov.w   R8, R12
        mov.w   R7, R13
        clr.w   R14
        mov.w   #DOWN, R15
        call    #gfx_card
        add.w   #DOWN, R7
        dec.w   R6
        jnz     1b
2:      mov.w   #8, R6                                  ; 8 cards in columns 0-2, 7 in 3-6: 52
        cmp.w   #3, R9
        jlo     3f
        mov.w   #7, R6
3:      mov.w   R10, R12
        call    #sheet_card                             ; R14 = card number R10, face up
        mov.w   R8, R12
        mov.w   R7, R13
        mov.w   #UP, R15
        cmp.w   #1, R6
        jne     4f
        mov.w   #CARD_H, R15                            ; the last shows whole
4:      call    #gfx_card
        add.w   #UP, R7
        inc.w   R10
        dec.w   R6
        jnz     3b
        inc.w   R9
        cmp.w   #7, R9
        jne     sheet_column

        ; text
        mov.w   #2, R12
        mov.w   #140, R13
        mov.w   #text_1, R14
        call    #gfx_text
        mov.w   #2, R12
        mov.w   #150, R13
        mov.w   #text_2, R14
        call    #gfx_text
        mov.w   #2, R12
        mov.w   #160, R13
        mov.w   #text_3, R14
        call    #gfx_text
        mov.w   #160, R13
        mov.w   #12345, R14
        call    #gfx_number                             ; after text_3
        mov.w   #160, R13
        mov.w   #text_4, R14
        call    #gfx_text
        mov.w   #160, R13
        clr.w   R14
        call    #gfx_number                             ; 0 still shows a digit

        popm.w  #7, R10
        ret

; sheet_card: the card for a number 0-51: spades A-K, clubs, hearts, diamonds.
;   in:      R12 = the number
;   out:     R14 = the card, face up
;   changes: R12, R14
sheet_card:
        clr.w   R14
1:      cmp.w   #13, R12
        jlo     2f
        sub.w   #13, R12
        add.w   #0x10, R14                              ; next suit
        jmp     1b
2:      inc.w   R12                                     ; ranks are 1-13
        add.w   R12, R14
        bis.w   #FACE_UP, R14
        ret

        .section .rodata
text_1: .asciz  "ABCDEFGHIJKLMNOPQRSTUVW"
text_2: .asciz  "XYZ 0123456789 !%'()+,-"
text_3: .asciz  "./:=? moves "              /* lower case, drawn as upper */
text_4: .asciz  " "
