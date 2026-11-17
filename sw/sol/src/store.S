; store.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
;
; What's kept in FRAM (STEP9-saving.md): the game, and the settings and statistics. .persistent is loaded with
; the program and kept across resets and power loss (never cleared by the start-up code), so the game survives
; the batteries coming out. Writing it needs store_open first; store_close seals the game with its checksum and
; protects FRAM again.
#include <msp430.h>
#include "sol.h"

/* A test build can start with draw 1 (-DTEST_DRAW=1) */
#ifndef TEST_DRAW
#define TEST_DRAW 3
#endif

        .section .persistent, "aw"
        .balign 2
        .global game_magic, seed, rng, deals, moves, draw, passes, won, last_move, max_passes, scoring, score
        .global undo_count, undo_next, undo_log, game_version, game_sum
        .global settings_magic, opt_draw, opt_passes, opt_scoring
        .global stat_played, stat_won, stat_streak, stat_best, wdt_resets
; ---- the game: everything from game_magic to game_version is covered by game_sum ----
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
last_move: .skip 4                                      ; the latest change's record (M_SOURCE ... in sol.h)
max_passes: .byte 0                                     ; passes through the stock allowed: 0 unlimited, 3 or 1
scoring: .byte  0                                       ; S_OFF, S_STANDARD or S_VEGAS
        .balign 2
score:  .word   0                                       ; the score, signed (Vegas starts at -52)
undo_count: .word 0                                     ; records in the undo log, 0 to UNDO_SIZE
undo_next: .byte 0                                      ; where the next record goes, 0 to UNDO_SIZE - 1
        .balign 2
undo_log: .skip 4 * UNDO_SIZE                           ; the undo log: a ring of move records
game_version: .word 0                                   ; STORE_VERSION: the layout this game was saved with
game_sum: .word 0                                       ; checksum of game_magic ... game_version (store_sum)
        .equ    GAME_WORDS, (game_sum - game_magic) / 2 ; the words game_sum covers
; ---- the settings and statistics: kept apart from the game, so a lost game doesn't lose them ----
settings_magic: .word SETTINGS_MAGIC                    ; the settings below are valid
opt_draw: .byte TEST_DRAW                               ; the options, for the next new game: draw 1 or 3
opt_passes: .byte 0                                     ; stock passes: 0 (unlimited), 3 or 1
opt_scoring: .byte 0                                    ; S_OFF, S_STANDARD or S_VEGAS
        .balign 2
stat_played: .word 0                                    ; games dealt
stat_won: .word 0                                       ; games won
stat_streak: .word 0                                    ; games won in a row, up to now
stat_best: .word 0                                      ; the longest streak
wdt_resets: .word 0                                     ; watchdog resets: a hang, caught (PLAN.md, Watchdog)

; pile_addr: each pile's address, by pile number (P_STOCK ... P_TAB1 + 6 in sol.h, and P_SCRATCH, game.S's
; scratch pile in RAM), for the pile routines in game.S
        .section .rodata
        .balign 2
        .global pile_addr
pile_addr:
        .word   stock, waste, found1, found2, found3, found4
        .word   tab1, tab2, tab3, tab4, tab5, tab6, tab7, scratch
pile_room:                                              ; each pile's room plus one, by pile number
        .byte   25, 25, 14, 14, 14, 14, 20, 20, 20, 20, 20, 20, 20

        .section .bss
seen:   .skip   64                                      ; cards_valid: one byte per card, by suit << 4 | rank

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

; store_close: seals the game with its checksum (game_sum, from store_sum), then protects program FRAM again.
; A game interrupted between store_open and store_close (the batteries pulled mid-move) is left unsealed, which
; store_valid notices.
;   in:      none
;   out:     none
;   changes: nothing
        .global store_close
store_close:
        push.w  R12
        call    #store_sum
        mov.w   R12, &game_sum
        pop.w   R12
        ; fall into store_protect

; store_protect: protects program FRAM again, without sealing the game: for changes to the settings and
; statistics only, so they can never seal a game left half-changed (store_valid must still see that).
;   in:      none
;   out:     none
;   changes: nothing
        .global store_protect
store_protect:
        mov.w   #FRWPPW|DFWP|PFWP, &SYSCFG0             ; password; both protected
        ret

; store_sum: the game's checksum: over the words from game_magic to game_version, sum = (sum rotated left one
; bit) + word. The rotation makes the order count, so swapped words change it.
;   in:      none
;   out:     R12 = the checksum
;   changes: R12 (the others it uses are saved)
        .global store_sum
store_sum:
        push.w  R13
        push.w  R14
        clr.w   R12
        mov.w   #game_magic, R13                        ; R13 = the next word
        mov.w   #GAME_WORDS, R14                        ; R14 = words left
1:      rla.w   R12                                     ; rotate left: the top bit out into carry...
        adc.w   R12                                     ; ...and back in at bit 0
        add.w   @R13+, R12
        dec.w   R14
        jnz     1b
        pop.w   R14
        pop.w   R13
        ret

; store_valid: whether FRAM holds a game to resume: GAME_MAGIC, this firmware's STORE_VERSION, and its checksum.
; A game whose checksum is wrong but whose cards are all there, each once (the power went off after a move
; finished but before its checksum was written, say), is kept but loses its undo log, and is sealed again.
;   in:      none
;   out:     R12 = 1 if there's a game, 0 if not
;   changes: R12-R15
        .global store_valid
store_valid:
        cmp.w   #GAME_MAGIC, &game_magic
        jne     2f
        cmp.w   #STORE_VERSION, &game_version
        jne     2f
        call    #store_sum
        cmp.w   &game_sum, R12
        jeq     1f                                      ; sealed: good
        call    #cards_valid                            ; unsealed: are the cards all there?
        tst.w   R12
        jz      2f
        call    #store_open                             ; keep the game, but not its undo log
        clr.w   &undo_count
        call    #store_close                            ; (seals it)
1:      mov.w   #1, R12
        ret
2:      clr.w   R12
        ret

; cards_valid: whether the piles hold each of the 52 cards exactly once, with every count in its pile's range.
;   in:      none
;   out:     R12 = 1 if so, 0 if not
;   changes: R12-R15
cards_valid:
        pushm.w #4, R10                                 ; R7-R10
        mov.w   #seen, R13                              ; clear seen: one byte per card
        mov.w   #64, R14
1:      clr.b   0(R13)
        inc.w   R13
        dec.w   R14
        jnz     1b
        clr.w   R10                                     ; R10 = the pile, 0-12
        clr.w   R9                                      ; R9 = cards counted
2:      mov.w   R10, R12
        rla.w   R12
        mov.w   pile_addr(R12), R8                      ; R8 = the pile
        mov.b   @R8, R7                                 ; R7 = its count
        cmp.b   pile_room(R10), R7
        jhs     8f                                      ; more than it can hold
        add.w   R7, R9
        tst.w   R7
        jz      4f
3:      inc.w   R8
        mov.b   @R8, R12
        and.w   #SUIT_MASK|RANK_MASK, R12               ; the card, without face up
        mov.w   R12, R13
        and.w   #RANK_MASK, R13
        jz      8f                                      ; rank 0: not a card
        cmp.w   #14, R13
        jhs     8f                                      ; rank over 13
        tst.b   seen(R12)
        jnz     8f                                      ; seen already
        mov.b   #1, seen(R12)
        dec.w   R7
        jnz     3b
4:      inc.w   R10
        cmp.w   #P_PILES, R10
        jne     2b
        cmp.w   #52, R9
        jne     8f                                      ; 52 distinct cards: all of them
        mov.w   #1, R12
        jmp     9f
8:      clr.w   R12
9:      popm.w  #4, R10
        ret

; settings_valid: makes sure the settings and statistics are usable: if settings_magic is wrong (never set, or
; damaged) or an option is out of range, puts the defaults back and clears the statistics.
;   in:      none
;   out:     none
;   changes: nothing
        .global settings_valid
settings_valid:
        cmp.w   #SETTINGS_MAGIC, &settings_magic
        jne     1f
        cmp.b   #1, &opt_draw
        jeq     2f
        cmp.b   #3, &opt_draw
        jne     1f
2:      tst.b   &opt_passes
        jeq     3f
        cmp.b   #1, &opt_passes
        jeq     3f
        cmp.b   #3, &opt_passes
        jne     1f
3:      cmp.b   #S_VEGAS+1, &opt_scoring
        jlo     4f                                      ; all good
1:      call    #store_open                             ; the defaults
        mov.b   #3, &opt_draw
        clr.b   &opt_passes
        clr.b   &opt_scoring
        clr.w   &stat_played
        clr.w   &stat_won
        clr.w   &stat_streak
        clr.w   &stat_best
        clr.w   &wdt_resets
        mov.w   #SETTINGS_MAGIC, &settings_magic
        call    #store_protect
4:      ret
