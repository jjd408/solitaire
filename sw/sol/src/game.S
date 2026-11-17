; game.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
#include <msp430.h>
#include "sol.h"
        .section .bss
        .global scratch
deck:   .skip   52                                      ; scratch for shuffling: 52 cards, one byte each
scratch: .skip  25                                      ; pile_move's scratch pile (P_SCRATCH): a count, 24 cards
        .text

; ---- random numbers: xorshift32 (Marsaglia), its 32-bit state in rng (store.S, saved with the game) ----

; rng_seed: starts the generator from a seed. 0 becomes 1, as xorshift's state must never be 0 (it would stay 0).
; The state is in FRAM (.persistent): call store_open first, or the write is ignored and the state stays 0.
;   in:      R13:R12 = the seed (high:low)
;   out:     none
;   changes: nothing
rng_seed:
        mov.w   R12, &rng                               ; store the seed as the state
        mov.w   R13, &rng+2
        tst.w   R12
        jnz     1f
        tst.w   R13
        jnz     1f
        mov.w   #1, &rng                                ; both words 0: use 1 instead
1:      ret

; rng_next: the next pseudo-random number: x ^= x << 13; x ^= x >> 17; x ^= x << 5. It goes through every
; 32-bit value but 0 before repeating. From seed 0x1234 the first four are 0x4A94F1F7, 0x41E50FE2, 0xE33EC22E,
; 0x5418EDF3. Writes the state to FRAM: store_open must have been called, else the state never changes and it
; returns the same number every time (0 on a fresh chip).
;   in:      none
;   out:     R13:R12 = the number (high:low), also the new state
;   changes: R11-R15
rng_next:
        mov.w   &rng, R12                               ; R13:R12 = x
        mov.w   &rng+2, R13
        mov.w   R12, R14                                ; x ^= x << 13: R15:R14 = a copy of x...
        mov.w   R13, R15
        mov.w   #13, R11                                ; ...shifted left 13 bits, one at a time
1:      rla.w   R14                                     ; low word left one bit; its top bit goes into carry
        rlc.w   R15                                     ; high word left one bit, carry coming in at bit 0
        dec.w   R11
        jnz     1b
        xor.w   R14, R12                                ; x ^= the copy, word by word
        xor.w   R15, R13
        mov.w   R13, R14                                ; x ^= x >> 17: copy >> 16: the high word moves down...
        clr.w   R15                                     ;    ...and the new high word is 0
        clrc                                            ; shift in a 0, not whatever carry holds
        rrc.w   R14                                     ; one more bit right: >> 17 in all
        xor.w   R14, R12                                ; x's low word ^= it; the high word ^= 0: unchanged
        mov.w   R12, R14                                ; x ^= x << 5: a copy...
        mov.w   R13, R15
        mov.w   #5, R11                                 ; ...shifted left 5 bits
2:      rla.w   R14
        rlc.w   R15
        dec.w   R11
        jnz     2b
        xor.w   R14, R12
        xor.w   R15, R13
        mov.w   R12, &rng                               ; keep the new state
        mov.w   R13, &rng+2
        ret                                             ; R13:R12 = the random number

; rng_below: a random number from 0 to n - 1: the next number's high word r, scaled by the hardware multiplier
; as (r x n) / 65536 (the product's high word). The bias is at most n / 65536, under 0.1% for a deck.
;   in:      R12 = n, 1-65535
;   out:     R12 = the number, 0 to n - 1
;   changes: R11-R15
rng_below:
        push.w  R12                                     ; n, kept on the stack: rng_next changes R12-R15
        call    #rng_next                               ; R13 = the random high word
        mov.w   R13, &MPY                               ; operand 1 (MPY = unsigned multiply)
        pop.w   &OP2                                    ; operand 2 = n; writing OP2 starts the multiply
        mov.w   &RESHI, R12                             ; the product's high word: 0 to n - 1
        ret

; ---- the deck ----

; make_deck: puts the 52 cards in deck, in order: spades A-K, then clubs, hearts, diamonds, all face down.
;   in:      none
;   out:     none
;   changes: R12-R15
make_deck:
        mov.w   #deck, R14                              ; R14 = where the next card goes
        mov.w   #SPADES, R13                            ; R13 = the suit: spades (0x00) first
1:      mov.w   #1, R12                                 ; R12 = the rank: ace (1) first
2:      mov.w   R13, R15
        bis.w   R12, R15                                ; R15 = suit | rank: the card
        mov.b   R15, 0(R14)                             ; store it
        inc.w   R14
        inc.w   R12                                     ; next rank
        cmp.w   #13+1, R12                              ; past the king (13)?
        jne     2b
        add.w   #0x10, R13                              ; next suit: 0x00, 0x10, 0x20, 0x30
        cmp.w   #DIAMONDS+0x10, R13                     ; past diamonds (0x30)?
        jne     1b
        ret

; shuffle: shuffles deck (Fisher-Yates): for i from 51 down to 1, swaps card i with a random card j from 0 to i.
; Every order of the 52 cards is equally likely (as far as the generator allows). FRAM must be writable
; (store_open), as rng_below changes the generator's state there.
;   in:      none
;   out:     none
;   changes: R11-R15
shuffle:
        push.w  R10
        mov.w   #51, R10                                ; R10 = i, the last place not yet settled
1:      mov.w   R10, R12
        inc.w   R12                                     ; n = i + 1: j can be anything from 0 to i
        call    #rng_below                              ; R12 = j (rng_below changes R11-R15; R10 survives)
        mov.b   deck(R10), R13                          ; swap deck[i] and deck[j]
        mov.b   deck(R12), R14
        mov.b   R14, deck(R10)
        mov.b   R13, deck(R12)
        dec.w   R10                                     ; next place down...
        jnz     1b                                      ; ...to 1 (place 0 is whatever is left)
        pop.w   R10
        ret

; ---- the piles (store.S): a count byte, then the cards from the bottom up; the top card is at offset count ----

; pile_count: how many cards a pile has.
;   in:      R12 = the pile (P_STOCK ... P_TAB1 + 6)
;   out:     R12 = its count
;   changes: R12
        .global pile_count
pile_count:
        rla.w   R12                                     ; pile_addr holds words
        mov.w   pile_addr(R12), R12
        mov.b   @R12, R12
        ret

; pile_top: a pile's top card.
;   in:      R12 = the pile
;   out:     R12 = its top card, or 0 if it's empty
;   changes: R12, R13
        .global pile_top
pile_top:
        rla.w   R12
        mov.w   pile_addr(R12), R13                     ; R13 = the pile
        mov.b   @R13, R12                               ; R12 = its count: the top card's offset
        tst.w   R12
        jz      1f                                      ; empty: 0
        add.w   R12, R13
        mov.b   @R13, R12
1:      ret

; pile_card: one card of a pile, counting from the bottom.
;   in:      R12 = the pile, R13 = which card (1 = the bottom, count = the top)
;   out:     R12 = the card
;   changes: R12
        .global pile_card
pile_card:
        rla.w   R12
        mov.w   pile_addr(R12), R12
        add.w   R13, R12
        mov.b   @R12, R12
        ret

; pile_push: puts a card on top of a pile. FRAM must be writable (store_open).
;   in:      R12 = the pile, R13 = the card
;   out:     none
;   changes: R12, R14, R15
        .global pile_push
pile_push:
        rla.w   R12
        mov.w   pile_addr(R12), R14                     ; R14 = the pile
        mov.b   @R14, R15
        inc.w   R15                                     ; one more card...
        mov.b   R15, 0(R14)                             ; ...in the count
        add.w   R15, R14
        mov.b   R13, 0(R14)                             ; the card at its new top
        ret

; pile_pop: takes the top card off a pile. FRAM must be writable (store_open); the pile mustn't be empty.
;   in:      R12 = the pile
;   out:     R12 = the card taken
;   changes: R12-R15
        .global pile_pop
pile_pop:
        rla.w   R12
        mov.w   pile_addr(R12), R14                     ; R14 = the pile
        mov.b   @R14, R15                               ; R15 = its count
        mov.w   R14, R13
        add.w   R15, R13
        mov.b   @R13, R12                               ; the top card
        dec.w   R15
        mov.b   R15, 0(R14)                             ; one card fewer
        ret

; pile_move: moves the top count cards of one pile onto another, keeping their order: through the scratch pile
; (popping them onto it reverses them; popping them off again puts them back). FRAM must be writable
; (store_open): the caller opens it once for the whole move, as it changes more than the piles.
;   in:      R12 = the source pile (with at least count cards), R13 = the destination pile, R14 = count (0: does
;            nothing)
;   out:     none
;   changes: R12-R15
pile_move:
        tst.w   R14
        jz      3f                                      ; no cards: nothing to do
        pushm.w #3, R10                                 ; R8-R10
        mov.w   R12, R8                                 ; R8 = the source
        mov.w   R13, R9                                 ; R9 = the destination
        mov.w   R14, R10                                ; R10 = cards still to take
1:      mov.w   R8, R12
        call    #pile_pop                               ; the source's top card...
        mov.w   R12, R13
        mov.w   #P_SCRATCH, R12
        call    #pile_push                              ; ...onto the scratch pile (reversed)
        dec.w   R10
        jnz     1b
2:      mov.w   #P_SCRATCH, R12
        call    #pile_pop                               ; the scratch pile's top card...
        mov.w   R12, R13
        mov.w   R9, R12
        call    #pile_push                              ; ...onto the destination (back in order)
        tst.b   &scratch                                ; scratch's count: 0 = empty
        jnz     2b                                      ; cards left: take the next
        popm.w  #3, R10
3:      ret

; card_red: tests a card's colour: Z clear if it's red (jnz red), set if it's black.
;   reg = the register holding the card
        .macro  card_red reg
        bit.b   #HEARTS, \reg
        .endm

; card_rank: leaves only a card's rank (1-13) in reg.
        .macro  card_rank reg
        and.w   #RANK_MASK, \reg
        .endm

; ---- the rules (PLAN.md, Rules) ----

; card_fits: whether a card may go on a pile. On a foundation: an ace if it's empty, else the same suit one rank
; higher than its top card. On a tableau column: a king if it's empty, else one rank lower than its top card,
; which must be face up, and the other colour. The stock and the waste take nothing this way.
;   in:      R12 = the card, R13 = the pile
;   out:     R12 = 1 if it fits, 0 if not
;   changes: R12-R15
        .global card_fits
card_fits:
        mov.w   R12, R14                                ; R14 = the card
        mov.w   R13, R15                                ; R15 = the pile
        mov.w   R13, R12
        call    #pile_top                               ; R12 = its top card, or 0 (changes only R12, R13)
        cmp.w   #P_FOUND1, R15
        jlo     8f                                      ; the stock or the waste
        cmp.w   #P_TAB1, R15
        jhs     3f                                      ; a column
        tst.w   R12                                     ; a foundation:
        jnz     1f
        card_rank R14                                   ;   empty: an ace
        cmp.w   #1, R14
        jeq     9f
        jmp     8f
1:      mov.w   R12, R13                                ;   else the same suit...
        xor.w   R14, R13
        bit.w   #SUIT_MASK, R13
        jnz     8f
        card_rank R12                                   ;   ...one rank higher
        inc.w   R12
        card_rank R14
        cmp.w   R12, R14
        jeq     9f
        jmp     8f
3:      cmp.w   #P_TAB1+7, R15
        jhs     8f                                      ; not a pile
        tst.w   R12                                     ; a column:
        jnz     4f
        card_rank R14                                   ;   empty: a king
        cmp.w   #13, R14
        jeq     9f
        jmp     8f
4:      bit.w   #FACE_UP, R12                           ;   else on a face-up card...
        jz      8f
        mov.w   R12, R13                                ;   ...of the other colour...
        xor.w   R14, R13
        card_red R13
        jz      8f
        card_rank R12                                   ;   ...one rank lower
        card_rank R14
        inc.w   R14
        cmp.w   R14, R12
        jeq     9f
8:      clr.w   R12                                     ; no
        ret
9:      mov.w   #1, R12                                 ; yes
        ret

; ---- moves (STEP6-moves.md) ----

; game_move: moves cards from one pile to another if the rules allow: one card to a foundation; to a column, the
; top card of the waste or a foundation, or from another column the run that fits (the face-up card that fits
; the column, and every card on it: there's never more than one that does). Then turns over a face-down card
; left on top of the source column, records the move (record_move) and checks for a win. A move that isn't
; allowed changes nothing. Opens FRAM for the changes and protects it again after.
;   in:      R12 = the source pile (the waste, a foundation or a column), R13 = the destination (a foundation
;            or a column)
;   out:     R12 = 1 if it moved, 0 if not
;   changes: R11-R15
        .global game_move
game_move:
        pushm.w #4, R10                                 ; R7-R10
        mov.w   R12, R7                                 ; R7 = the source
        mov.w   R13, R8                                 ; R8 = the destination
        cmp.w   R7, R8
        jeq     8f                                      ; the same pile
        cmp.w   #P_WASTE, R7
        jlo     8f                                      ; from the stock: that's game_stock's
        cmp.w   #P_TAB1+7, R7
        jhs     8f
        cmp.w   #P_FOUND1, R8
        jlo     8f                                      ; to the stock or the waste: never
        cmp.w   #P_TAB1+7, R8
        jhs     8f
        mov.w   R7, R12
        call    #pile_count
        mov.w   R12, R9                                 ; R9 = cards in the source
        tst.w   R9
        jz      8f                                      ; nothing to move
        mov.w   #1, R10                                 ; R10 = how many to move: one...
        cmp.w   #P_TAB1, R8
        jlo     3f                                      ; ...to a foundation
        cmp.w   #P_TAB1, R7
        jlo     3f                                      ; ...from the waste or a foundation
        mov.w   R9, R10                                 ; column to column: R10 = a card's place, from the top
1:      mov.w   R7, R12
        mov.w   R10, R13
        call    #pile_card
        bit.w   #FACE_UP, R12
        jz      8f                                      ; past the face-up cards: none fits
        mov.w   R8, R13
        call    #card_fits
        tst.w   R12
        jnz     2f                                      ; this one
        dec.w   R10
        jnz     1b
        jmp     8f                                      ; (the column was all face up, and none fit)
2:      mov.w   R9, R12                                 ; the run: from that card to the top
        sub.w   R10, R12
        inc.w   R12
        mov.w   R12, R10                                ; R10 = how many
        jmp     4f
3:      mov.w   R7, R12                                 ; one card: the top must fit
        call    #pile_top
        mov.w   R8, R13
        call    #card_fits
        tst.w   R12
        jz      8f
4:      call    #store_open
        mov.w   R7, R12
        mov.w   R8, R13
        mov.w   R10, R14
        call    #pile_move
        mov.w   R7, R12
        call    #turn_over                              ; R12 = M_TURNED if it turned one, else 0
        mov.w   R12, R15                                ; the record: source, destination, count, flags
        mov.w   R7, R12
        mov.w   R8, R13
        mov.w   R10, R14
        call    #record_move
        call    #check_win
        call    #store_close
        mov.w   #1, R12
        jmp     9f
8:      clr.w   R12
9:      popm.w  #4, R10
        ret

; game_to_foundation: moves a pile's top card to whichever foundation takes it, the first of 1-4 that does (for
; the same button pressed twice).
;   in:      R12 = the pile (the waste or a column)
;   out:     R12 = the foundation it went to (P_FOUND1 ...), or 0 if none takes it
;   changes: R11-R15
        .global game_to_foundation
game_to_foundation:
        pushm.w #3, R10                                 ; R8-R10
        mov.w   R12, R10                                ; R10 = the pile
        cmp.w   #P_WASTE, R10
        jeq     1f
        cmp.w   #P_TAB1, R10
        jlo     8f                                      ; only the waste and the columns
1:      mov.w   R10, R12
        call    #pile_top
        mov.w   R12, R9                                 ; R9 = its top card
        tst.w   R9
        jz      8f                                      ; empty
        mov.w   #P_FOUND1, R8                           ; R8 = the foundation to try
2:      mov.w   R9, R12
        mov.w   R8, R13
        call    #card_fits
        tst.w   R12
        jnz     3f
        inc.w   R8
        cmp.w   #P_FOUND1+4, R8
        jne     2b
        jmp     8f                                      ; none takes it
3:      mov.w   R10, R12
        mov.w   R8, R13
        call    #game_move
        tst.w   R12
        jz      8f
        mov.w   R8, R12
        jmp     9f
8:      clr.w   R12
9:      popm.w  #3, R10
        ret

; turn_over: turns a column's top card face up if it's face down (the cards on it have just moved away).
;   in:      R12 = the pile
;   out:     R12 = M_TURNED if it turned one over, else 0
;   changes: R12, R13
turn_over:
        cmp.w   #P_TAB1, R12
        jlo     1f                                      ; only columns
        rla.w   R12
        mov.w   pile_addr(R12), R13
        mov.b   @R13, R12                               ; its count
        tst.w   R12
        jz      1f
        add.w   R12, R13                                ; R13 = the top card's address
        bit.b   #FACE_UP, 0(R13)
        jnz     1f
        bis.b   #FACE_UP, 0(R13)
        mov.w   #M_TURNED, R12
        ret
1:      clr.w   R12
        ret

; turn_back: turns a pile's top card face down (undoing turn_over).
;   in:      R12 = the pile
;   out:     none
;   changes: R12, R13
turn_back:
        rla.w   R12
        mov.w   pile_addr(R12), R13
        mov.b   @R13, R12
        add.w   R12, R13
        bic.b   #FACE_UP, 0(R13)
        ret

; record_move: records a change in last_move and the undo log (a ring: past UNDO_SIZE records the oldest are
; forgotten), and counts it in moves and the score. FRAM must be writable (store_open).
;   in:      R12 = the source pile, R13 = the destination, R14 = the count, R15 = the flags (M_TURNED, M_RECYCLED)
;   out:     none
;   changes: R12-R15
record_move:
        mov.b   R12, &last_move+M_SOURCE
        mov.b   R13, &last_move+M_DEST
        mov.b   R14, &last_move+M_COUNT
        mov.b   R15, &last_move+M_FLAGS
        mov.b   &undo_next, R12
        rlam.w  #2, R12                                 ; 4 bytes a record (last_move is at an odd address, so
        mov.b   &last_move+0, undo_log+0(R12)           ;   byte by byte)
        mov.b   &last_move+1, undo_log+1(R12)
        mov.b   &last_move+2, undo_log+2(R12)
        mov.b   &last_move+3, undo_log+3(R12)
        inc.b   &undo_next                              ; 255 + 1 is 0 in a byte: round the ring (UNDO_SIZE 256)
        cmp.w   #UNDO_SIZE, &undo_count
        jhs     1f                                      ; full: the oldest was just overwritten
        inc.w   &undo_count
1:      inc.w   &moves
        call    #score_delta
        add.w   R12, &score
        ret

; score_delta: what last_move is worth, by the game's scoring (PLAN.md, Options). Standard: waste to a column +5,
; waste or a column to a foundation +10, a foundation to a column -15, a card turned over +5, the waste turned
; back over in draw 1 -100. Vegas: a card onto a foundation +5, off one -5. Off: 0.
;   in:      none (last_move)
;   out:     R12 = the change in the score (signed)
;   changes: R12-R15
score_delta:
        clr.w   R12                                     ; R12 = the change
        mov.b   &last_move+M_SOURCE, R14                ; R14 = the source
        mov.b   &last_move+M_DEST, R15                  ; R15 = the destination
        cmp.b   #S_STANDARD, &scoring
        jeq     standard
        cmp.b   #S_VEGAS, &scoring
        jne     9f
        call    #to_from_foundation                     ; Vegas: R13 = +1 onto a foundation, -1 off one
        mov.w   R13, R12
        rlam.w  #2, R12                                 ; x 5
        add.w   R13, R12
        ret
standard:
        bit.b   #M_TURNED, &last_move+M_FLAGS
        jz      1f
        add.w   #5, R12                                 ; a card turned over
1:      bit.b   #M_RECYCLED, &last_move+M_FLAGS
        jz      2f
        cmp.b   #1, &draw
        jne     9f
        sub.w   #100, R12                               ; the waste turned over, in draw 1
        ret
2:      call    #to_from_foundation
        cmp.w   #1, R13
        jne     3f
        add.w   #10, R12                                ; onto a foundation (from the waste or a column)
        ret
3:      tst.w   R13
        jz      4f
        sub.w   #15, R12                                ; off a foundation
        ret
4:      cmp.b   #P_WASTE, R14
        jne     9f
        cmp.b   #P_TAB1, R15
        jlo     9f
        add.w   #5, R12                                 ; the waste to a column
9:      ret

; to_from_foundation: whether a move goes onto a foundation from elsewhere, or off one to elsewhere.
;   in:      R14 = the source, R15 = the destination
;   out:     R13 = 1 onto a foundation, -1 off one, else 0
;   changes: R13
to_from_foundation:
        clr.w   R13
        cmp.b   #P_FOUND1, R15                          ; destination a foundation?
        jlo     1f
        cmp.b   #P_TAB1, R15
        jhs     1f
        inc.w   R13
1:      cmp.b   #P_FOUND1, R14                          ; source a foundation?
        jlo     2f
        cmp.b   #P_TAB1, R14
        jhs     2f
        dec.w   R13
2:      ret

; check_win: if all four foundations hold 13 cards, the game is won: sets won and counts the win, the streak and
; the best streak. FRAM must be writable (store_open).
;   in:      none
;   out:     none
;   changes: R12-R14
check_win:
        mov.w   #P_FOUND1, R14
1:      mov.w   R14, R12
        call    #pile_count
        cmp.w   #13, R12
        jne     2f                                      ; not yet
        inc.w   R14
        cmp.w   #P_FOUND1+4, R14
        jne     1b
        mov.b   #1, &won                                ; won
        inc.w   &stat_won
        inc.w   &stat_streak
        cmp.w   &stat_streak, &stat_best                ; best - streak
        jhs     2f                                      ; the best is still the best
        mov.w   &stat_streak, &stat_best
2:      ret

; game_undo: takes back the latest move in the undo log, exactly: the cards go back where they came from (a card
; it turned over is turned back down; a deal goes back onto the stock face down; a turned-over waste is dealt
; back out, face up), and the move count, the passes and the score go back too. last_move gets the undone
; record, so ui.S knows what to redraw. Does nothing if the log is empty or the game is won. Opens FRAM for the
; changes and protects it again after.
;   in:      none
;   out:     R12 = 1 if it undid a move, 0 if not
;   changes: R11-R15
        .global game_undo
game_undo:
        tst.w   &undo_count
        jz      8f                                      ; nothing to undo
        tst.b   &won
        jnz     8f                                      ; a won game stays won
        call    #store_open
        dec.w   &undo_count
        dec.b   &undo_next                              ; 0 - 1 is 255 in a byte: back round the ring
        mov.b   &undo_next, R12
        rlam.w  #2, R12
        mov.b   undo_log+0(R12), &last_move+0           ; the record, into last_move
        mov.b   undo_log+1(R12), &last_move+1
        mov.b   undo_log+2(R12), &last_move+2
        mov.b   undo_log+3(R12), &last_move+3
        call    #score_delta                            ; the score and the count go back
        sub.w   R12, &score
        dec.w   &moves
        mov.b   &last_move+M_COUNT, R14
        bit.b   #M_RECYCLED, &last_move+M_FLAGS
        jz      1f
        mov.w   #P_STOCK, R12                           ; the waste was turned over: deal it back out, face up
        mov.w   #P_WASTE, R13
        mov.w   #FACE_UP, R15
        call    #pile_deal
        dec.b   &passes
        jmp     3f
1:      cmp.b   #P_STOCK, &last_move+M_SOURCE
        jne     2f
        mov.w   #P_WASTE, R12                           ; a deal: the cards go back onto the stock, face down
        mov.w   #P_STOCK, R13
        clr.w   R15
        call    #pile_deal
        jmp     3f
2:      bit.b   #M_TURNED, &last_move+M_FLAGS           ; a move: turn back the card it turned over...
        jz      4f
        mov.b   &last_move+M_SOURCE, R12
        call    #turn_back
4:      mov.b   &last_move+M_DEST, R12                  ; ...and move the cards back, in order
        mov.b   &last_move+M_SOURCE, R13
        mov.b   &last_move+M_COUNT, R14
        call    #pile_move
3:      call    #store_close
        mov.w   #1, R12
        ret
8:      clr.w   R12
        ret

; ---- a new game ----

; game_new: shuffles a new deck and deals a game from it, as dealt by hand: a row at a time across the tableau
; (column n gets n cards, the last face up), the other 24 to the stock face down. Takes the rules from the
; options (draw, passes, scoring), starts the game's counts and its undo log, and keeps the seed. Counts the
; game in the statistics: one more played, and a streak ends if the game before wasn't won. Counts the deal and
; marks the game as there. Draws nothing.
;   in:      R13:R12 = the seed (high:low)
;   out:     none
;   changes: R11-R15
        .global game_new
game_new:
        pushm.w #3, R10                                 ; R8-R10
        call    #store_open                             ; the generator's state and the piles are in FRAM
        cmp.w   #GAME_MAGIC, &game_magic                ; the statistics: a game left unwon ends the streak
        jne     6f
        tst.b   &won
        jnz     6f
        clr.w   &stat_streak
6:      inc.w   &stat_played
        mov.w   R12, &seed
        mov.w   R13, &seed+2
        call    #rng_seed
        call    #make_deck
        call    #shuffle
        mov.w   #P_PILES-1, R10                         ; empty all 13 piles: their counts to 0
1:      mov.w   R10, R12
        rla.w   R12
        mov.w   pile_addr(R12), R12
        clr.b   0(R12)
        dec.w   R10
        jge     1b                                      ; 12 down to 0
        clr.w   R9                                      ; R9 = the next card in the deck, 0-51
        clr.w   R8                                      ; R8 = the row, 0-6
2:      mov.w   R8, R10                                 ; R10 = the column: the row's own first (column = row)
3:      mov.b   deck(R9), R13                           ; the next card...
        inc.w   R9
        cmp.w   R8, R10
        jne     4f
        bis.w   #FACE_UP, R13                           ; ...face up if it's this column's last (its own row)
4:      mov.w   R10, R12
        add.w   #P_TAB1, R12
        call    #pile_push                              ; ...onto the column
        inc.w   R10
        cmp.w   #7, R10
        jne     3b                                      ; across to column 7
        inc.w   R8
        cmp.w   #7, R8
        jne     2b                                      ; down to row 7: 28 cards dealt
5:      mov.b   deck(R9), R13                           ; the other 24 to the stock, face down
        mov.w   #P_STOCK, R12
        call    #pile_push
        inc.w   R9
        cmp.w   #52, R9
        jne     5b
        mov.b   &opt_draw, &draw                        ; the rules, from the options
        mov.b   &opt_passes, &max_passes
        mov.b   &opt_scoring, &scoring
        clr.w   &score                                  ; the counts
        cmp.b   #S_VEGAS, &scoring
        jne     7f
        mov.w   #VEGAS_START, &score                    ; Vegas: you've paid 52 for the deck
7:      clr.w   &moves
        clr.b   &passes
        clr.b   &won
        clr.b   &last_move+0
        clr.b   &last_move+1
        clr.b   &last_move+2
        clr.b   &last_move+3
        clr.w   &undo_count                             ; nothing to undo
        clr.b   &undo_next
        inc.w   &deals                                  ; one more game dealt, ever
        mov.w   #STORE_VERSION, &game_version
        mov.w   #GAME_MAGIC, &game_magic                ; there's a game
        call    #store_close                            ; (seals it)
        popm.w  #3, R10
        ret

; ---- the stock ----

; pile_deal: moves count cards from one pile to another, one at a time, turning each face up or face down. Their
; order reverses, as when dealing from your hand. FRAM must be writable (store_open).
;   in:      R12 = the source pile (with at least count cards), R13 = the destination pile, R14 = count, 1 or more,
;            R15 = FACE_UP to turn them face up, 0 to turn them face down
;   out:     none
;   changes: R12-R15
pile_deal:
        pushm.w #4, R10                                 ; R7-R10
        mov.w   R12, R7                                 ; R7 = the source
        mov.w   R13, R8                                 ; R8 = the destination
        mov.w   R14, R9                                 ; R9 = cards still to move
        mov.w   R15, R10                                ; R10 = FACE_UP or 0
1:      mov.w   R7, R12
        call    #pile_pop                               ; the source's top card...
        mov.w   R12, R13
        bic.w   #FACE_UP, R13
        bis.w   R10, R13                                ; ...turned as asked...
        mov.w   R8, R12
        call    #pile_push                              ; ...onto the destination
        dec.w   R9
        jnz     1b
        popm.w  #4, R10
        ret

; game_stock: the stock button. With cards in the stock, deals draw of them (3, or 1; fewer if fewer are left)
; to the waste one at a time, face up, so the last one dealt is the waste's top. With the stock empty, turns the
; whole waste back over into the stock, face down, restoring the stock's order for the next pass, and counts a
; pass; unless the game's passes are used up (max_passes: 3 passes allow 2 turn-overs). Either way, records the
; move (record_move). Opens FRAM for the changes and protects it again after.
;   in:      none
;   out:     R12 = STOCK_DONE if it dealt or turned the waste over, STOCK_NONE if there was nothing to do (the
;            stock and the waste empty), STOCK_LIMIT if the waste can't be turned over (no passes left)
;   changes: R11-R15
        .global game_stock
game_stock:
        push.w  R10
        mov.w   #P_STOCK, R12
        call    #pile_count
        mov.w   R12, R10                                ; R10 = cards in the stock
        tst.w   R10
        jnz     2f                                      ; cards in the stock: deal
        mov.w   #P_WASTE, R12
        call    #pile_count
        mov.w   R12, R10                                ; R10 = cards in the waste
        tst.w   R10
        jz      4f                                      ; both empty: nothing to do
        tst.b   &max_passes
        jz      1f                                      ; unlimited passes
        mov.b   &passes, R12
        inc.w   R12                                     ; passes made, counting the first
        cmp.b   &max_passes, R12
        jhs     5f                                      ; all used
1:      call    #store_open
        mov.w   #P_WASTE, R12                           ; turn the whole waste over into the stock...
        mov.w   #P_STOCK, R13
        mov.w   R10, R14
        clr.w   R15                                     ; ...face down
        call    #pile_deal
        inc.b   &passes
        mov.w   #P_WASTE, R12                           ; the record: waste to stock, every card, turned over
        mov.w   #P_STOCK, R13
        mov.w   R10, R14
        mov.w   #M_RECYCLED, R15
        jmp     3f
2:      cmp.b   &draw, R10                              ; the stock's count - draw
        jlo     6f                                      ; fewer left than draw: deal them all
        mov.b   &draw, R10                              ; R10 = cards to deal
6:      call    #store_open
        mov.w   #P_STOCK, R12
        mov.w   #P_WASTE, R13
        mov.w   R10, R14
        mov.w   #FACE_UP, R15                           ; face up
        call    #pile_deal
        mov.w   #P_STOCK, R12                           ; the record: stock to waste, the cards dealt
        mov.w   #P_WASTE, R13
        mov.w   R10, R14
        clr.w   R15
3:      call    #record_move
        call    #store_close
        mov.w   #STOCK_DONE, R12
        pop.w   R10
        ret
4:      mov.w   #STOCK_NONE, R12
        pop.w   R10
        ret
5:      mov.w   #STOCK_LIMIT, R12
        pop.w   R10
        ret
