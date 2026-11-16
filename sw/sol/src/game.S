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
        and.b   #RANK_MASK, \reg
        .endm

; ---- a new game ----

; game_new: shuffles a new deck and deals a game from it, as dealt by hand: a row at a time across the tableau
; (column n gets n cards, the last face up), the other 24 to the stock face down. Keeps the seed, counts the
; deal and marks the game as there. Draws nothing.
;   in:      R13:R12 = the seed (high:low)
;   out:     none
;   changes: R11-R15
        .global game_new
game_new:
        pushm.w #3, R10                                 ; R8-R10
        call    #store_open                             ; the generator's state and the piles are in FRAM
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
        inc.w   &deals                                  ; one more game dealt, ever
        mov.w   #GAME_MAGIC, &game_magic                ; there's a game
        call    #store_close
        popm.w  #3, R10
        ret
