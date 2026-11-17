; ui.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
;
; The interface (STEP7-interface.md): what a button means, and drawing the table (PLAN.md, Layout):
;
;   y 2     [stock] [waste...]   [ F1 ] [ F2 ] [ F3 ] [ F4 ]    columns 0, 1 (fanned in draw 3) and 3-6
;   y 30    [T1]  [T2]  [T3]  [T4]  [T5]  [T6]  [T7]           columns 0-6, fanned downward, to y 157
;   y 159   MOVES n      SCORE n                DRAW n         the status line, small font, to y 167
;
; Moves take two presses: a source (a column, the waste or a foundation: its top card is shown inverted), then
; a destination. The same button twice sends the card to a foundation. A move that isn't allowed shows a message
; and keeps the selection. Only the piles that changed are redrawn.
#include <msp430.h>
#include "sol.h"

        .section .bss
        .global mode
sel:    .skip   1                                       ; the selected pile (the move's source), or 0
confirm: .skip  1                                       ; NEW pressed once mid-game: press again to deal
mode:   .skip   1                                       ; MODE_TABLE or MODE_OPTIONS
        .balign 2
msg:    .skip   2                                       ; a message for the status line, or 0; lasts one press
        .global redraw
redraw: .skip   2                                       ; what ui_update draws: a bit per pile, R_STATUS, R_ALL
sd:     .skip   1                                       ; draw_column: face-down strips' height...
su:     .skip   1                                       ; ...and face-up strips', squeezed to fit
col_bottom: .skip 7                                     ; each column's last drawn line + 1 (0: not known), so
                                                        ;   a redraw clears and sends only the lines it used

        .section .rodata
role_pile:                                              ; the pile a button stands for, by role, or 0
        .byte   0                                       ; B_NONE
        .byte   P_TAB1, P_TAB1+1, P_TAB1+2, P_TAB1+3, P_TAB1+4, P_TAB1+5, P_TAB1+6
        .byte   P_WASTE, 0                              ; B_WASTE, B_STOCK (not a source or destination)
        .byte   P_FOUND1, P_FOUND1+1, P_FOUND1+2, P_FOUND1+3
        .byte   0, 0, 0                                 ; B_NEW, B_UNDO, B_OPTIONS
        .balign 2
pile_bit:                                               ; a pile's bit in redraw
        .word   1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096
title_text: .asciz "SOLITAIRE"
press_text: .asciz "PRESS NEW TO DEAL"
moves_text: .asciz "MOVES "
score_text: .asciz "SCORE "
draw_text: .asciz "DRAW "
minus_text: .asciz "-"
win_text: .asciz "YOU WIN!"
won_text: .asciz "WON "
of_text: .asciz " OF "
again_text: .asciz "PRESS NEW TO DEAL AGAIN"
confirm_text: .asciz "PRESS NEW AGAIN FOR A NEW GAME"
undo_text: .asciz "NOTHING TO UNDO"
passes_text: .asciz "NO PASSES LEFT"
empty_text: .asciz "NOTHING THERE"
cant_text: .asciz "CAN'T GO THERE"

        .text

; ui_start: what to show at power-up: the game kept in FRAM if there's a valid one (store_valid), else the title
; screen. Checks the settings and statistics too.
;   in:      none
;   out:     none
;   changes: R11-R15
        .global ui_start
ui_start:
#ifdef TEST_CORRUPT
        cmp.w   #GAME_MAGIC, &game_magic                ; a test build damages the kept game at every start,
        jne     21f                                     ;   as a power cut mid-change might (STEP9-saving.md)
        call    #store_open
#if TEST_CORRUPT == 1
        inc.w   &moves                                  ; 1: a count changed after the seal: the cards are fine
#else
        mov.w   &pile_addr + 2 * P_TAB1, R12            ; 2: column 1's bottom card a copy of column 2's
        mov.w   &pile_addr + 2 * (P_TAB1 + 1), R13
        mov.b   1(R13), 1(R12)
#endif
        call    #store_protect                          ; (not sealed)
21:
#endif
        call    #settings_valid
        call    #store_valid
        tst.w   R12
        jnz     1f
        call    #store_open                             ; no game, or a broken one: forget it
        clr.w   &game_magic
        call    #store_close
1:      clr.b   &sel
        clr.b   &confirm
        clr.b   &mode
        clr.w   &msg
        mov.w   #R_ALL, &redraw
        jmp     ui_update

; ui_button: does what a button means (STEP7-interface.md), then redraws what changed.
;   in:      R12 = the button's role (B_...)
;   out:     none
;   changes: R11-R15
        .global ui_button
ui_button:
        push.w  R10
        mov.w   R12, R10                                ; R10 = the role
        bis.w   #R_STATUS, &redraw                      ; the status line, every time
        cmp.b   #MODE_OPTIONS, &mode
        jne     1f
        call    #options_button                         ; the options screen has the buttons
        jmp     done
1:      clr.w   &msg                                    ; a message lasts until the next press
        cmp.w   #B_OPTIONS, R10
        jne     2f
        call    #deselect                               ; OPTIONS: the options screen
        clr.b   &confirm
        call    #options_open
        jmp     done
2:      cmp.w   #GAME_MAGIC, &game_magic
        jne     no_game
        tst.b   &won
        jnz     no_game                                 ; won: only NEW (no need to confirm)
        cmp.w   #B_NEW, R10
        jne     3f
        call    #deselect                               ; NEW mid-game: press it twice
        tst.w   &moves
        jz      new                                     ; (nothing played yet: no need to ask)
        tst.b   &confirm
        jnz     new
        mov.b   #1, &confirm
        mov.w   #confirm_text, &msg
        jmp     done
no_game:
        cmp.w   #B_NEW, R10
        jne     done                                    ; nothing else does anything
new:    clr.b   &confirm
        call    #new_game
        jmp     done
3:      clr.b   &confirm                                ; any other button: no new game after all
        cmp.w   #B_UNDO, R10
        jne     4f
        call    #deselect                               ; UNDO
        call    #game_undo
        tst.w   R12
        jz      5f
        call    #redraw_last
        jmp     done
5:      mov.w   #undo_text, &msg
        jmp     done
4:      cmp.w   #B_STOCK, R10
        jne     6f
        call    #deselect                               ; STOCK: deal, or turn the waste over
        call    #game_stock
        cmp.w   #STOCK_DONE, R12
        jne     7f
        call    #redraw_last
        jmp     done
7:      cmp.w   #STOCK_LIMIT, R12
        jne     done
        mov.w   #passes_text, &msg
        jmp     done
6:      mov.b   role_pile(R10), R10                     ; a pile's button: R10 = the pile
        tst.w   R10
        jz      done
        tst.b   &sel
        jnz     8f
        mov.w   R10, R12                                ; nothing selected: select it, if it has a card
        call    #pile_count
        tst.w   R12
        jz      9f
        mov.b   R10, &sel
        mov.w   R10, R12
        call    #mark
        jmp     done
9:      mov.w   #empty_text, &msg
        jmp     done
8:      cmp.b   &sel, R10
        jne     10f
        call    #deselect                               ; the same button twice: to a foundation, if it fits
        mov.w   R10, R12
        call    #game_to_foundation
        tst.w   R12
        jz      done                                    ; (if not, it's only deselected)
        call    #redraw_last
        jmp     11f
10:     mov.b   &sel, R12                               ; another pile: move there, if the rules allow
        mov.w   R10, R13
        call    #game_move
        tst.w   R12
        jz      12f
        call    #deselect
        call    #redraw_last
11:     tst.b   &won
        jz      done
        bis.w   #R_ALL, &redraw                         ; won: the win screen
        jmp     done
12:     mov.w   #cant_text, &msg                        ; not allowed: say so, and keep the selection
done:   call    #ui_update
        pop.w   R10
        ret

; new_game: deals a new game and has it all redrawn. The seed is when NEW was pressed, mixed with the number of
; games dealt (STEP5-game.md); a test build (-DTEST_SEED=...) always deals the same game.
;   in:      none
;   out:     none
;   changes: R11-R15
new_game:
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
        clr.b   &sel
        mov.w   #R_ALL, &redraw
        ret

; deselect: drops the selection, if there is one, and has its pile redrawn.
;   in:      none
;   out:     none
;   changes: R12
deselect:
        mov.b   &sel, R12
        tst.w   R12
        jz      1f
        clr.b   &sel
        jmp     mark
1:      ret

; redraw_last: has the piles last_move touched redrawn (after a move, a deal or an undo).
;   in:      none
;   out:     none
;   changes: R12
redraw_last:
        mov.b   &last_move+M_SOURCE, R12
        call    #mark
        mov.b   &last_move+M_DEST, R12
        ; fall into mark

; mark: has a pile redrawn by the next ui_update.
;   in:      R12 = the pile
;   out:     none
;   changes: R12
mark:
        rla.w   R12
        bis.w   pile_bit(R12), &redraw
        ret

; ui_update: draws what redraw asks for, and clears it: everything (the title screen if there's no game; else the
; table, the status line and, once the game is won, the win screen over it), or just the marked piles and the
; status line. The options screen draws itself (options.S).
;   in:      none
;   out:     none
;   changes: R11-R15
        .global ui_update
ui_update:
        push.w  R10
        cmp.b   #MODE_OPTIONS, &mode
        jeq     9f                                      ; the options screen: drawn already
        cmp.w   #GAME_MAGIC, &game_magic
        jeq     1f
        bit.w   #R_ALL, &redraw                         ; no game: the title screen
        jz      9f
        call    #ui_title
        jmp     9f
1:      bit.w   #R_ALL, &redraw
        jz      2f
        call    #gfx_clear                              ; everything
        bis.w   #0x1FFF|R_STATUS, &redraw
        mov.w   #6, R12                                 ; the columns are blank now: nothing to clear
21:     mov.b   #TABLE_Y, col_bottom(R12)
        dec.w   R12
        jge     21b
2:      clr.w   R10                                     ; R10 = the pile, 0-12
3:      mov.w   R10, R12
        rla.w   R12
        bit.w   pile_bit(R12), &redraw
        jz      4f
        mov.w   R10, R12
        call    #draw_pile
4:      inc.w   R10
        cmp.w   #P_PILES, R10
        jne     3b
        bit.w   #R_STATUS, &redraw
        jz      5f
        call    #draw_status
5:      bit.w   #R_ALL, &redraw
        jz      9f
        tst.b   &won
        jz      9f
        call    #draw_win                               ; won: the win screen, over the table
9:      clr.w   &redraw
        pop.w   R10
        ret

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

; draw_pile: draws one pile in its place (clearing what was there).
;   in:      R12 = the pile
;   out:     none
;   changes: R11-R15
draw_pile:
        cmp.w   #P_WASTE, R12
        jlo     draw_stock
        jeq     draw_waste
        cmp.w   #P_TAB1, R12
        jlo     draw_found
        jmp     draw_column

; draw_stock: the stock: a card's back while it has cards, else an empty place.
draw_stock:
        mov.w   #P_STOCK, R12
        call    #pile_count
        tst.w   R12
        mov.w   #COL_X(0), R12                          ; (mov doesn't change the flags tst set)
        mov.w   #TOP_Y, R13
        jz      1f
        clr.w   R14                                     ; face down: its back
        mov.w   #CARD_H, R15
        br      #gfx_card                               ; (its ret returns for us)
1:      br      #gfx_slot

; draw_waste: the waste: its top card, or in draw 3 its top three fanned across, the top one whole; selected
; (inverted) if it's the move's source.
draw_waste:
        pushm.w #4, R10                                 ; R7-R10
        mov.w   #COL_X(1), R12                          ; clear its place: 2 columns wide
        mov.w   #TOP_Y, R13
        mov.w   #2 * 20, R14
        mov.w   #CARD_H, R15
        call    #gfx_white
        mov.w   #P_WASTE, R12
        call    #pile_count
        mov.w   R12, R9                                 ; R9 = its count
        tst.w   R9
        jnz     1f
        mov.w   #COL_X(1), R12                          ; empty
        mov.w   #TOP_Y, R13
        call    #gfx_slot
        jmp     9f
1:      mov.w   #1, R10                                 ; R10 = cards to show: 1...
        cmp.b   #3, &draw
        jne     2f
        mov.w   #3, R10                                 ; ...3 in draw 3...
        cmp.w   R10, R9
        jhs     2f
        mov.w   R9, R10                                 ; ...or as many as there are
2:      mov.w   R9, R8                                  ; R8 = the first shown card's place
        sub.w   R10, R8
        inc.w   R8
        mov.w   #COL_X(1), R7                           ; R7 = x
3:      mov.w   #P_WASTE, R12
        mov.w   R8, R13
        call    #pile_card
        mov.w   R12, R14                                ; R14 = the card
        cmp.w   R9, R8
        jne     4f
        cmp.b   #P_WASTE, &sel                          ; the top one: selected?
        jne     4f
        bis.w   #SELECTED, R14
4:      mov.w   R7, R12
        mov.w   #TOP_Y, R13
        mov.w   #CARD_H, R15
        call    #gfx_card
        add.w   #WASTE_FAN, R7
        inc.w   R8
        cmp.w   R8, R9
        jhs     3b                                      ; to the top
9:      popm.w  #4, R10
        ret

; draw_found: a foundation: its top card (selected if it's the move's source), or an empty place.
draw_found:
        push.w  R10
        mov.w   R12, R10                                ; R10 = the pile
        sub.w   #P_FOUND1 - 3, R12                      ; columns 3-6
        mov.w   R12, R13
        call    #column_x
        push.w  R13                                     ; x (pile_top changes R13)
        mov.w   R10, R12
        call    #pile_top
        mov.w   R12, R14                                ; R14 = the card, or 0
        pop.w   R12                                     ; R12 = x
        mov.w   #TOP_Y, R13
        tst.w   R14
        jz      2f
        cmp.b   &sel, R10
        jne     1f
        bis.w   #SELECTED, R14
1:      mov.w   #CARD_H, R15
        call    #gfx_card
        pop.w   R10
        ret
2:      call    #gfx_slot
        pop.w   R10
        ret

; draw_column: a tableau column, in its 128 lines: face-down cards as strips of 3 lines, face-up ones as strips
; of 10, the last card whole and selected (inverted) if the column is the move's source. A column too tall to
; fit is squeezed (PLAN.md, Layout): first the face-down strips, down to 1 line; then the face-up ones, down to 8.
; Clears only the lines the column took last time (col_bottom), as every line drawn has to be sent.
;   in:      R12 = the pile (P_TAB1 ...)
draw_column:
        pushm.w #7, R10                                 ; R4-R10
        mov.w   R12, R10                                ; R10 = the pile
        sub.w   #P_TAB1, R12
        mov.w   R12, R13
        call    #column_x
        mov.w   R13, R6                                 ; R6 = x
        mov.w   R10, R12                                ; clear what it took last time (all of its place if
        sub.w   #P_TAB1, R12                            ;   that isn't known)
        mov.b   col_bottom(R12), R15
        tst.w   R15
        jnz     11f
        mov.w   #TABLE_Y + TABLE_H, R15
11:     sub.w   #TABLE_Y, R15
        mov.w   R6, R12
        mov.w   #TABLE_Y, R13
        mov.w   #CARD_W, R14
        call    #gfx_white
        mov.w   R10, R12
        call    #pile_count
        mov.w   R12, R9                                 ; R9 = its count
        tst.w   R9
        jnz     1f
        mov.w   R6, R12                                 ; empty: its place
        mov.w   #TABLE_Y, R13
        call    #gfx_slot
        mov.w   #TABLE_Y + CARD_H, R7                   ; (its bottom)
        jmp     9f
1:      clr.w   R4                                      ; R4 = face-down strips: the face-down cards (all at the
        mov.w   #1, R8                                  ;   bottom), but not the last card
2:      cmp.w   R9, R8
        jhs     3f
        mov.w   R10, R12
        mov.w   R8, R13
        call    #pile_card
        bit.w   #FACE_UP, R12
        jnz     3f
        inc.w   R4
        inc.w   R8
        jmp     2b
3:      mov.w   R9, R5                                  ; R5 = face-up strips: the rest but the last
        dec.w   R5
        sub.w   R4, R5
        mov.b   #STRIP_DOWN, &sd
        mov.b   #STRIP_UP, &su
4:      call    #strips_height                          ; squeeze until the strips and a whole card fit
        cmp.w   #TABLE_H - CARD_H + 1, R12
        jlo     6f                                      ; it fits
        cmp.b   #STRIP_DOWN_MIN + 1, &sd
        jlo     5f
        dec.b   &sd                                     ; first the face-down strips...
        jmp     4b
5:      cmp.b   #STRIP_UP_MIN + 1, &su
        jlo     6f                                      ; (can't squeeze more: never needed, by the rules)
        dec.b   &su                                     ; ...then the face-up ones
        jmp     4b
6:      mov.w   #TABLE_Y, R7                            ; R7 = y
        mov.w   #1, R8                                  ; R8 = the card's place, from the bottom
7:      mov.w   R10, R12
        mov.w   R8, R13
        call    #pile_card
        mov.w   R12, R14                                ; R14 = the card
        mov.w   #CARD_H, R15                            ; the last card shows whole...
        cmp.w   R9, R8
        jne     8f
        cmp.b   &sel, R10                               ; ...selected if the column is the source
        jne     10f
        bis.w   #SELECTED, R14
        jmp     10f
8:      mov.b   &sd, R15                                ; ...the others a strip
        bit.w   #FACE_UP, R14
        jz      10f
        mov.b   &su, R15
10:     mov.w   R6, R12
        mov.w   R7, R13
        add.w   R15, R7                                 ; the next card starts below this one's strip
        call    #gfx_card
        inc.w   R8
        cmp.w   R8, R9
        jhs     7b                                      ; while place <= count
9:      mov.w   R10, R12                                ; R7 = its bottom, for next time
        sub.w   #P_TAB1, R12
        mov.b   R7, col_bottom(R12)
        popm.w  #7, R10
        ret

; strips_height: the lines a column's strips take: face-down strips x sd + face-up strips x su.
;   in:      R4 = face-down strips, R5 = face-up strips
;   out:     R12 = the lines
;   changes: R12-R14
strips_height:
        clr.w   R12
        mov.b   &sd, R14
        mov.w   R4, R13
1:      tst.w   R13
        jz      2f
        add.w   R14, R12
        dec.w   R13
        jmp     1b
2:      mov.b   &su, R14
        mov.w   R5, R13
3:      tst.w   R13
        jz      4f
        add.w   R14, R12
        dec.w   R13
        jmp     3b
4:      ret

; draw_status: the status line: a message if there is one, inverted across the line; else the move count, the
; score (with scoring on) and the draw.
;   in:      none
;   out:     none
;   changes: R11-R15
draw_status:
        clr.w   R12
        mov.w   #STATUS_TOP, R13
        mov.w   #LCD_W, R14
        mov.w   #LCD_H - STATUS_TOP, R15
        call    #gfx_white
        tst.w   &msg
        jz      1f
        mov.w   &msg, R12                               ; a message, centred...
        call    #gfx_text_width_small
        mov.w   #LCD_W, R13
        sub.w   R12, R13
        rra.w   R13
        mov.w   R13, R12
        mov.w   #STATUS_Y, R13
        mov.w   &msg, R14
        call    #gfx_text_small
        clr.w   R12                                     ; ...white on black
        mov.w   #STATUS_TOP, R13
        mov.w   #LCD_W, R14
        mov.w   #LCD_H - STATUS_TOP, R15
        br      #gfx_invert
1:      mov.w   #2, R12                                 ; MOVES n
        mov.w   #STATUS_Y, R13
        mov.w   #moves_text, R14
        call    #gfx_text_small
        mov.w   #STATUS_Y, R13
        mov.w   &moves, R14
        call    #gfx_number_small
        tst.b   &scoring
        jz      2f
        mov.w   #56, R12                                ; SCORE n
        mov.w   #STATUS_Y, R13
        mov.w   #score_text, R14
        call    #gfx_text_small
        mov.w   #STATUS_Y, R13
        mov.w   &score, R14
        call    #signed_small
2:      mov.w   #LCD_W - 2 - (6 * 4 - 1), R12           ; DRAW n, at the right: 6 characters
        mov.w   #STATUS_Y, R13
        mov.w   #draw_text, R14
        call    #gfx_text_small
        mov.w   #STATUS_Y, R13
        mov.b   &draw, R14
        br      #gfx_number_small

; signed_small: draws a signed number in the small font.
;   in:      R12 = x, R13 = y (top), R14 = the number (-32768 to 32767)
;   out:     R12 = x after the last digit
;   changes: R11-R15
signed_small:
        tst.w   R14
        jge     1f
        push.w  R14
        push.w  R13
        mov.w   #minus_text, R14
        call    #gfx_text_small
        pop.w   R13
        pop.w   R14
        inv.w   R14                                     ; the number without its sign
        inc.w   R14
1:      br      #gfx_number_small

; draw_win: the win screen, a box over the middle of the table: YOU WIN!, the moves, the score (with scoring
; on), the games won so far, and how to go on.
;   in:      none
;   out:     none
;   changes: R11-R15
#define WIN_X 16
#define WIN_Y 48
#define WIN_W 112
#define WIN_H 70
draw_win:
        mov.w   #WIN_X, R12                             ; a black frame, 2 pixels...
        mov.w   #WIN_Y, R13
        mov.w   #WIN_W, R14
        mov.w   #WIN_H, R15
        call    #gfx_black
        mov.w   #WIN_X + 2, R12                         ; ...around white
        mov.w   #WIN_Y + 2, R13
        mov.w   #WIN_W - 4, R14
        mov.w   #WIN_H - 4, R15
        call    #gfx_white
        mov.w   #(LCD_W - 8 * 6 + 1) / 2, R12           ; YOU WIN!, centred: 8 characters, 6 pixels each
        mov.w   #WIN_Y + 8, R13
        mov.w   #win_text, R14
        call    #gfx_text
        mov.w   #WIN_X + 10, R12                        ; MOVES n
        mov.w   #WIN_Y + 24, R13
        mov.w   #moves_text, R14
        call    #gfx_text_small
        mov.w   #WIN_Y + 24, R13
        mov.w   &moves, R14
        call    #gfx_number_small
        tst.b   &scoring
        jz      1f
        mov.w   #WIN_X + 10, R12                        ; SCORE n
        mov.w   #WIN_Y + 32, R13
        mov.w   #score_text, R14
        call    #gfx_text_small
        mov.w   #WIN_Y + 32, R13
        mov.w   &score, R14
        call    #signed_small
1:      mov.w   #WIN_X + 10, R12                        ; WON n OF n
        mov.w   #WIN_Y + 40, R13
        mov.w   #won_text, R14
        call    #gfx_text_small
        mov.w   #WIN_Y + 40, R13
        mov.w   &stat_won, R14
        call    #gfx_number_small
        mov.w   #WIN_Y + 40, R13
        mov.w   #of_text, R14
        call    #gfx_text_small
        mov.w   #WIN_Y + 40, R13
        mov.w   &stat_played, R14
        call    #gfx_number_small
        mov.w   #(LCD_W - 23 * 4 + 1) / 2, R12          ; PRESS NEW TO DEAL AGAIN, centred: 23 characters
        mov.w   #WIN_Y + 56, R13
        mov.w   #again_text, R14
        br      #gfx_text_small

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
