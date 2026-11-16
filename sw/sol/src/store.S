; store.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
#include <msp430.h>

; The game, in FRAM: .persistent is loaded with the program and kept across resets and power loss (never
; cleared by the start-up code), so the game survives the batteries coming out. Writing it needs
; store_open first.
        .section .persistent, "aw"
        .balign 2
        .global game_magic, seed, rng, deals, moves, draw, passes, won, last_move
game_magic: .word 0                                     ; GAME_MAGIC once a game has been dealt
seed:   .word   0, 0                                    ; the deal's seed (32 bits)
rng:    .word   0, 0                                    ; the generator's state
deals:  .word   0                                       ; games dealt, ever: mixed into each seed
; The piles: a count byte, then room for the most cards the pile can hold (its top card is at count)
stock:  .skip   25                                      ; up to 24 cards
waste:  .skip   25                                      ; up to 24
found1: .skip   14                                      ; foundations: up to 13 each
found2: .skip   14
found3: .skip   14
found4: .skip   14
tab1:   .skip   20                                      ; tableau: up to 19 each (6 face down + 13 face up)
tab2:   .skip   20
tab3:   .skip   20
tab4:   .skip   20
tab5:   .skip   20
tab6:   .skip   20
tab7:   .skip   20
; The game in play: its rules, its progress and its last move
        .balign 2                                       ; moves is a word: on an even address whatever comes before
moves:  .word   0                                       ; moves made this game, for the status line
draw:   .byte   3                                       ; cards a stock move deals, 1 or 3: set by game_new
passes: .byte   0                                       ; times the waste has been turned back into the stock
won:    .byte   0                                       ; non-zero once the game is won
last_move: .skip 4                                      ; the last move's record (M_SOURCE ... in sol.h)

; pile_addr: each pile's address, by pile number (P_STOCK ... P_TAB1 + 6 in sol.h, and P_SCRATCH, game.S's
; scratch pile in RAM), for the pile routines in game.S
        .section .rodata
        .balign 2
        .global pile_addr
pile_addr:
        .word   stock, waste, found1, found2, found3, found4
        .word   tab1, tab2, tab3, tab4, tab5, tab6, tab7, scratch

        .text

; store_open: makes program FRAM writable, for changing the game. SYSCFG0.PFWP protects it (code, constants and
; .persistent alike) from stray writes; every change to the game goes between store_open and store_close, so
; it's writable only for those few instructions.
;   in:      none
;   out:     none
;   changes: nothing
        .global store_open
store_open:
        mov.w   #FRWPPW|DFWP, &SYSCFG0                  ; password; PFWP clear, info FRAM still protected
        ret

; store_close: protects program FRAM again.
;   in:      none
;   out:     none
;   changes: nothing
        .global store_close
store_close:
        mov.w   #FRWPPW|DFWP|PFWP, &SYSCFG0             ; password; both protected
        ret

