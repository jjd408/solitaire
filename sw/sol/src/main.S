; main.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
#include <msp430.h>
#include "sol.h"

/* Which test screen to show until the game exists: 1 the step 2 pattern, 2 the step 3 card sheet. The tests
   choose with -DTEST_SCREEN=n; NetBeans builds the latest. */
#ifndef TEST_SCREEN
#define TEST_SCREEN 2
#endif

        .section .bss
        events:.skip 16; the event queue
        
        .text

; main: calls init routines. falls into lower power sleep until interrupt.
;   in:      none
;   out:     none
;   changes: none
        .global main
main:
        call    #system                 ; init clocks and io ports
        call    #lcd                    ; init display
#if TEST_SCREEN == 1
        call    #test_pattern           ; step 2's test picture
#else
        call    #card_sheet             ; step 3's sheet of cards
#endif
loop:
        mov.w   #WDT_RUN, &WDTCTL       ; kick the watchdog
        call    #lcd_flush
        bis     #LPM3_bits|GIE, SR      ; low power sleep
        nop
        jmp     loop
        
