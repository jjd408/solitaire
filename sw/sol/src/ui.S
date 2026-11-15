; ui.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
;
; The interface: what a button means, and drawing the table (PLAN.md, Layout):
;
;   y 2     [stock] [waste]   [ F1 ] [ F2 ] [ F3 ] [ F4 ]       columns 0, 1 and 3-6, 20 pixels apart
;   y 30    [T1]  [T2]  [T3]  [T4]  [T5]  [T6]  [T7]           columns 0-6, fanned downward
;   y 161   GAME n                                              the status line, small font
#include <msp430.h>
#include "sol.h"

        .section .rodata
title_text: .asciz "SOLITAIRE"
press_text: .asciz "PRESS NEW TO DEAL"
game_text:  .asciz "GAME "

        .text

; ui_start: what to show at power-up: the game if there is one (it's kept in FRAM), else the title screen.
;   in:      none
;   out:     none
;   changes: R11-R15
        .global ui_start
ui_start:
        cmp.w   #GAME_MAGIC, &game_magic
        jne     ui_title
        jmp     ui_draw

; ui_button: does what a button means. For now only NEW does anything: it deals a new game and draws it.
;   in:      R12 = the button's role (B_...)
;   out:     none
;   changes: R11-R15
        .global ui_button
ui_button:
        cmp.w   #B_NEW, R12
        jne     1f
#ifdef TEST_SEED
        mov.w   #(TEST_SEED) & 0xFFFF, R12              ; a test build: always the same deal
        mov.w   #((TEST_SEED) >> 16) & 0xFFFF, R13
#else
        mov.w   &press_time, R12                        ; the seed: when NEW was pressed (to 2 ms)...
        xor.w   #0x79B9, R12
        mov.w   &deals, R13                             ; ...and how many games have been dealt, so two
        xor.w   #0x9E37, R13                            ;    presses at the same count still differ
#endif
        call    #game_new
        jmp     ui_draw                                 ; (its ret returns for us)
1:      ret

; ui_title: the screen before any game has been dealt.
;   in:      none
;   out:     none
;   changes: R11-R15
        .global ui_title
ui_title:
        call    #gfx_clear
        mov.w   #(LCD_W - 9 * 6 + 1) / 2, R12           ; "SOLITAIRE", centred: 9 characters, 6 pixels each
        mov.w   #64, R13
        mov.w   #title_text, R14
        call    #gfx_text
        mov.w   #(LCD_W - 17 * 4 + 1) / 2, R12          ; and the hint, 17 small characters, 4 pixels each
        mov.w   #84, R13
        mov.w   #press_text, R14
        call    #gfx_text_small
        ret

; ui_draw: draws the whole table from the piles: stock, waste, foundations, the seven columns and the status
; line. Marks every line dirty; lcd_flush sends it.
;   in:      none
;   out:     none
;   changes: R11-R15
        .global ui_draw
ui_draw:
        pushm.w #5, R10                                 ; R6-R10
        call    #gfx_clear
        ; the stock: a back while it has cards, else an empty place
        mov.w   #P_STOCK, R12
        call    #pile_count
        tst.w   R12
        mov.w   #COL_X(0), R12                          ; (mov doesn't change the flags tst set)
        mov.w   #TOP_Y, R13
        jz      1f
        clr.w   R14                                     ; face down: its back
        mov.w   #CARD_H, R15
        call    #gfx_card
        jmp     2f
1:      call    #gfx_slot
        ; the waste, and foundations 1-4: each top card, or an empty place
2:      mov.w   #P_WASTE, R12
        mov.w   #COL_X(1), R13
        call    #draw_top
        clr.w   R10                                     ; R10 = foundation 0-3, at column 3 + R10
3:      mov.w   R10, R12
        add.w   #P_FOUND1, R12
        mov.w   R10, R13
        call    #column_x                               ; R13 = x of column R13...
        add.w   #3 * 20, R13                            ; ...moved on three columns
        call    #draw_top
        inc.w   R10
        cmp.w   #4, R10
        jne     3b
        ; the tableau: R10 = column 0-6, R6 = x, R7 = y, R8 = card 1..count, R9 = count
        clr.w   R10
4:      mov.w   R10, R13
        call    #column_x
        mov.w   R13, R6
        mov.w   #TABLE_Y, R7
        mov.w   R10, R12
        add.w   #P_TAB1, R12
        call    #pile_count
        mov.w   R12, R9
        tst.w   R9
        jnz     5f
        mov.w   R6, R12                                 ; an empty column: its place
        mov.w   R7, R13
        call    #gfx_slot
        jmp     7f
5:      mov.w   #1, R8                                  ; from the bottom card up
6:      mov.w   R10, R12
        add.w   #P_TAB1, R12
        mov.w   R8, R13
        call    #pile_card
        mov.w   R12, R14                                ; R14 = the card
        mov.w   #CARD_H, R15                            ; the last card shows whole...
        cmp.w   R9, R8
        jeq     8f
        mov.w   #STRIP_DOWN, R15                        ; ...the others a strip: 3 lines face down,
        bit.b   #FACE_UP, R14
        jz      8f
        mov.w   #STRIP_UP, R15                          ;    10 face up
8:      mov.w   R6, R12
        mov.w   R7, R13
        add.w   R15, R7                                 ; the next card starts below this one's strip
        call    #gfx_card
        inc.w   R8
        cmp.w   R8, R9
        jhs     6b                                      ; while card <= count
7:      inc.w   R10
        cmp.w   #7, R10
        jne     4b
        ; the status line: the game's number
        mov.w   #2, R12
        mov.w   #STATUS_Y, R13
        mov.w   #game_text, R14
        call    #gfx_text_small
        mov.w   #STATUS_Y, R13
        mov.w   &deals, R14
        call    #gfx_number_small
        popm.w  #5, R10
        ret

; column_x: a column's x: 2 + 20 * column (COL_X in sol.h, worked out at run time).
;   in:      R13 = the column, 0-6
;   out:     R13 = its x
;   changes: R13, R15
column_x:
        rlam.w  #2, R13                                 ; column * 4
        mov.w   R13, R15
        rlam.w  #2, R15                                 ; column * 16
        add.w   R15, R13                                ; column * 20
        add.w   #2, R13
        ret

; draw_top: draws a pile's top card in the top row, or an empty place if it has none.
;   in:      R12 = the pile, R13 = x
;   out:     none
;   changes: R11-R15
draw_top:
        push.w  R13                                     ; x, as pile_top changes R13
        call    #pile_top
        mov.w   R12, R14                                ; R14 = the card, or 0
        pop.w   R12                                     ; R12 = x
        mov.w   #TOP_Y, R13
        tst.w   R14
        jz      1f
        mov.w   #CARD_H, R15
        br      #gfx_card                               ; (its ret returns for us)
1:      br      #gfx_slot
