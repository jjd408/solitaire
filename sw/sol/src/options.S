; options.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
;
; The options screen (PLAN.md, Options; STEP8-undo-options.md), in place of the game while it's open:
;
;   y 4     OPTIONS
;   y 22    S1  DRAW            3 CARDS            each setting beside the suit button that steps through it
;   y 32    S2  STOCK PASSES    UNLIMITED
;   y 42    S3  SCORING         OFF
;   y 52    S4  RESET STATISTICS                  (press twice)
;   y 64    CHANGES APPLY TO THE NEXT GAME
;   y 80    STATISTICS
;   y 96... PLAYED, WON (with the rate), STREAK, BEST STREAK, WATCHDOG RESETS (if any)
;   y 161   OPTIONS: BACK TO THE GAME
;
; The settings are kept in FRAM (store.S) and apply from the next new game: a game keeps the rules it was dealt
; with.
#include <msp430.h>
#include "sol.h"

        .section .bss
arm:    .skip   1                                       ; S4 pressed once: press again to reset the statistics

        .section .rodata
options_text: .asciz "OPTIONS"
s1_text: .asciz "S1"
s2_text: .asciz "S2"
s3_text: .asciz "S3"
s4_text: .asciz "S4"
draw_label: .asciz "DRAW"
passes_label: .asciz "STOCK PASSES"
scoring_label: .asciz "SCORING"
reset_label: .asciz "RESET STATISTICS"
reset_again: .asciz "PRESS AGAIN TO RESET"
next_text: .asciz "CHANGES APPLY TO THE NEXT GAME"
stats_text: .asciz "STATISTICS"
played_label: .asciz "PLAYED"
won_label: .asciz "WON"
streak_label: .asciz "STREAK"
best_label: .asciz "BEST STREAK"
resets_label: .asciz "WATCHDOG RESETS"
back_text: .asciz "OPTIONS: BACK TO THE GAME"
one_card: .asciz "1 CARD"
three_cards: .asciz "3 CARDS"
unlimited: .asciz "UNLIMITED"
off_text: .asciz "OFF"
standard_text: .asciz "STANDARD"
vegas_text: .asciz "VEGAS"
open_paren: .asciz " ("
pct_close: .asciz "%)"
        .balign 2
scoring_names:                                          ; by S_OFF, S_STANDARD, S_VEGAS
        .word   off_text, standard_text, vegas_text

#define LABEL_X 16                                      /* where the labels start */
#define VALUE_X 80                                      /* where the values start */

        .text

; options_open: opens the options screen.
;   in:      none
;   out:     none
;   changes: R11-R15
        .global options_open
options_open:
        mov.b   #MODE_OPTIONS, &mode
        clr.b   &arm
        jmp     options_draw

; options_button: a button on the options screen. S1-S3 step through draw (3, 1), stock passes (unlimited, 3,
; 1) and scoring (off, standard, Vegas); S4 twice resets the statistics; OPTIONS goes back to the game. The
; others do nothing.
;   in:      R12 = the button's role
;   out:     none
;   changes: R11-R15
        .global options_button
options_button:
        cmp.w   #B_OPTIONS, R12
        jne     1f
        clr.b   &arm                                    ; back to the game, all redrawn
        mov.b   #MODE_TABLE, &mode
        mov.w   #R_ALL, &redraw
        ret
1:      cmp.w   #B_FOUND4, R12
        jeq     reset
        clr.b   &arm                                    ; any other button: no reset after all
        call    #store_open
        cmp.w   #B_FOUND1, R12
        jne     2f
        xor.b   #1 ^ 3, &opt_draw                       ; draw: 3 <-> 1
        jmp     9f
2:      cmp.w   #B_FOUND2, R12
        jne     4f
        mov.b   &opt_passes, R13                        ; passes: unlimited (0) -> 3 -> 1 -> unlimited
        mov.b   #3, R14
        tst.w   R13
        jz      3f
        mov.b   #1, R14
        cmp.w   #3, R13
        jeq     3f
        clr.w   R14
3:      mov.b   R14, &opt_passes
        jmp     9f
4:      cmp.w   #B_FOUND3, R12
        jne     9f
        inc.b   &opt_scoring                            ; scoring: off -> standard -> Vegas -> off
        cmp.b   #S_VEGAS + 1, &opt_scoring
        jlo     9f
        clr.b   &opt_scoring
9:      call    #store_protect
        jmp     options_draw
reset:
        tst.b   &arm
        jnz     1f
        mov.b   #1, &arm                                ; S4 once: ask
        jmp     options_draw
1:      clr.b   &arm                                    ; S4 again: reset
        call    #store_open
        clr.w   &stat_played
        clr.w   &stat_won
        clr.w   &stat_streak
        clr.w   &stat_best
        clr.w   &wdt_resets
        call    #store_protect
        jmp     options_draw

; options_draw: draws the options screen.
;   in:      none
;   out:     none
;   changes: R11-R15
options_draw:
        call    #gfx_clear
        mov.w   #(LCD_W - 7 * 6 + 1) / 2, R12           ; OPTIONS, centred
        mov.w   #4, R13
        mov.w   #options_text, R14
        call    #gfx_text
        ; S1 DRAW n CARD(S)
        mov.w   #22, R13
        mov.w   #s1_text, R14
        mov.w   #draw_label, R15
        call    #setting
        mov.w   #three_cards, R14
        cmp.b   #1, &opt_draw
        jne     1f
        mov.w   #one_card, R14
1:      mov.w   #22, R13
        call    #value
        ; S2 STOCK PASSES n
        mov.w   #32, R13
        mov.w   #s2_text, R14
        mov.w   #passes_label, R15
        call    #setting
        tst.b   &opt_passes
        jnz     2f
        mov.w   #unlimited, R14
        mov.w   #32, R13
        call    #value
        jmp     3f
2:      mov.w   #VALUE_X, R12
        mov.w   #32, R13
        mov.b   &opt_passes, R14
        call    #gfx_number_small
        ; S3 SCORING ...
3:      mov.w   #42, R13
        mov.w   #s3_text, R14
        mov.w   #scoring_label, R15
        call    #setting
        mov.b   &opt_scoring, R14
        rla.w   R14
        mov.w   scoring_names(R14), R14
        mov.w   #42, R13
        call    #value
        ; S4 RESET STATISTICS, or the question
        mov.w   #reset_label, R15
        tst.b   &arm
        jz      4f
        mov.w   #reset_again, R15
4:      mov.w   #52, R13
        mov.w   #s4_text, R14
        call    #setting
        mov.w   #4, R12
        mov.w   #64, R13
        mov.w   #next_text, R14
        call    #gfx_text_small
        ; STATISTICS
        mov.w   #(LCD_W - 10 * 6 + 1) / 2, R12
        mov.w   #80, R13
        mov.w   #stats_text, R14
        call    #gfx_text
        mov.w   #96, R13                                ; PLAYED n
        mov.w   #played_label, R14
        mov.w   &stat_played, R15
        call    #statistic
        mov.w   #106, R13                               ; WON n (r%)
        mov.w   #won_label, R14
        mov.w   &stat_won, R15
        call    #statistic
        tst.w   &stat_played
        jz      5f
        mov.w   #106, R13
        mov.w   #open_paren, R14
        call    #gfx_text_small
        push.w  R12
        mov.w   &stat_won, R12
        mov.w   &stat_played, R13
        call    #percent
        mov.w   R12, R14
        pop.w   R12
        mov.w   #106, R13
        call    #gfx_number_small
        mov.w   #106, R13
        mov.w   #pct_close, R14
        call    #gfx_text_small
5:      mov.w   #116, R13                               ; STREAK n
        mov.w   #streak_label, R14
        mov.w   &stat_streak, R15
        call    #statistic
        mov.w   #126, R13                               ; BEST STREAK n
        mov.w   #best_label, R14
        mov.w   &stat_best, R15
        call    #statistic
        tst.w   &wdt_resets
        jz      6f
        mov.w   #136, R13                               ; WATCHDOG RESETS n, only if there were any
        mov.w   #resets_label, R14
        mov.w   &wdt_resets, R15
        call    #statistic
6:      mov.w   #(LCD_W - 25 * 4 + 1) / 2, R12          ; OPTIONS: BACK TO THE GAME, centred
        mov.w   #STATUS_Y, R13
        mov.w   #back_text, R14
        br      #gfx_text_small

; setting: a setting's button name and label, in the small font.
;   in:      R13 = y, R14 = the button's name ("S1"), R15 = the label
;   out:     none
;   changes: R11-R15
setting:
        push.w  R15
        push.w  R13
        mov.w   #4, R12
        call    #gfx_text_small
        pop.w   R13
        pop.w   R14
        mov.w   #LABEL_X, R12
        br      #gfx_text_small

; value: a setting's value, in the small font, in the values' column.
;   in:      R13 = y, R14 = the text
;   out:     none
;   changes: R11-R15
value:
        mov.w   #VALUE_X, R12
        br      #gfx_text_small

; statistic: a statistic's label and number, in the small font.
;   in:      R13 = y, R14 = the label, R15 = the number
;   out:     R12 = x after the number
;   changes: R11-R15
statistic:
        push.w  R15
        push.w  R13
        mov.w   #LABEL_X, R12
        call    #gfx_text_small
        pop.w   R13
        pop.w   R14
        mov.w   #VALUE_X, R12
        br      #gfx_number_small

; percent: a share as a whole percentage, rounded down: R12 x 100 / R13. The product (up to 32 bits) comes from
; the hardware multiplier; the division is by repeated subtraction, at most 100 times as R12 <= R13.
;   in:      R12 = the part, R13 = the whole (not 0, and at least the part)
;   out:     R12 = the percentage, 0-100
;   changes: R12-R15
percent:
        mov.w   R12, &MPY                               ; unsigned multiply: operand 1...
        mov.w   #100, &OP2                              ; ...operand 2 starts it
        mov.w   &RESLO, R14                             ; R15:R14 = part x 100
        mov.w   &RESHI, R15
        clr.w   R12                                     ; R12 = the quotient
1:      tst.w   R15                                     ; R15:R14 >= the whole?
        jnz     2f
        cmp.w   R13, R14
        jlo     3f
2:      sub.w   R13, R14                                ; take the whole away
        sbc.w   R15
        inc.w   R12
        jmp     1b
3:      ret
