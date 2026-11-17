; testsqueeze.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
;
; The test screen for step 7's squeeze (PLAN.md, Layout; built with -DTEST_SCREEN=4): a made-up game whose
; columns are every height that matters, then the game screen as usual (and the buttons work on it):
;
;   column  face down  face up   fits by
;   1       0          1         (a single card)
;   2       6          9         normal strips: 6 x 3 + 8 x 10 + 26 = 124 lines
;   3       6          10        face-down strips squeezed to 2
;   4       6          13        the tallest legal column: face down 1, face up 8, an exact fit (128 lines)
;   5       0          13        face up 8
;   6       3          12        face down 1, face up 9
;   7       5          11        face down 1, face up 9
;
; The cards aren't a real deal (the face-down ones repeat), so it's sealed as it is: store_valid checks only
; the checksum when it matches.
#include <msp430.h>
#include "sol.h"

        .section .rodata
squeeze_piles:                                          ; pile, count, the cards from the bottom up; then 0xFF
        .byte   6, 1, 0xAD
        .byte   7, 15, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x8D, 0xAC, 0x9B, 0xBA, 0x89, 0xA8, 0x97, 0xB6, 0x85
        .byte   8, 16, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0xAD, 0x8C, 0xBB, 0x9A, 0xA9, 0x88, 0xB7, 0x96, 0xA5, 0x84
        .byte   9, 19, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x8D, 0xAC, 0x9B, 0xBA, 0x89, 0xA8, 0x97, 0xB6, 0x85, 0xA4, 0x93, 0xB2, 0x81
        .byte   10, 13, 0xAD, 0x8C, 0xBB, 0x9A, 0xA9, 0x88, 0xB7, 0x96, 0xA5, 0x84, 0xB3, 0x92, 0xA1
        .byte   11, 15, 0x01, 0x02, 0x03, 0x8D, 0xAC, 0x9B, 0xBA, 0x89, 0xA8, 0x97, 0xB6, 0x85, 0xA4, 0x93, 0xB2
        .byte   12, 16, 0x01, 0x02, 0x03, 0x04, 0x05, 0xAD, 0x8C, 0xBB, 0x9A, 0xA9, 0x88, 0xB7, 0x96, 0xA5, 0x84, 0xB3
        .byte   0, 4, 0x05, 0x06, 0x07, 0x08
        .byte   1, 3, 0x89, 0xA4, 0xB7
        .byte   2, 2, 0x81, 0x82
        .byte   3, 1, 0xA1
        .byte   0xFF

        .text

; squeeze_screen: sets up the made-up game in FRAM, then shows it with ui_start.
;   in:      none
;   out:     none
;   changes: R11-R15
        .global squeeze_screen
squeeze_screen:
        push.w  R10
        push.w  R9
        call    #store_open
        mov.w   #P_PILES-1, R12                         ; empty the piles
1:      mov.w   R12, R13
        rla.w   R13
        mov.w   pile_addr(R13), R13
        clr.b   0(R13)
        dec.w   R12
        jge     1b
        mov.w   #squeeze_piles, R10                     ; R10 = the table
2:      mov.b   @R10+, R9                               ; R9 = the pile, or 0xFF at the end
        cmp.b   #0xFF, R9
        jeq     4f
        mov.b   @R10+, R11                              ; R11 = how many cards
3:      mov.b   @R10+, R13
        mov.w   R9, R12
        call    #pile_push                              ; (changes R12, R14, R15)
        dec.w   R11
        jnz     3b
        jmp     2b
4:      mov.b   #3, &draw                               ; a game in draw 3, nothing to undo
        clr.w   &moves
        clr.b   &won
        clr.b   &scoring
        clr.w   &undo_count
        mov.w   #STORE_VERSION, &game_version
        mov.w   #GAME_MAGIC, &game_magic
        call    #store_close                            ; (seals it)
        pop.w   R9
        pop.w   R10
        br      #ui_start
