; main.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
#include <msp430.h>
#include "sol.h"
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
        call    #test_pattern           ; draw the test picture (step 2)
loop:   
        mov.w   #WDT_RUN, &WDTCTL       ; kick the watchdog
        call    #lcd_flush
        bis     #LPM3_bits|GIE, SR      ; low power sleep
        nop
        jmp     loop
        
