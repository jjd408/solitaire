; system.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
#include <msp430.h>
#include "sol.h"

        .section __interrupt_vector_42,"ax",@progbits   ; TIMER0_B1_VECTOR
        .word   tb0_wrap_isr

        .text

; system: sets up the board, genericset up of io. sets up the clocks.
;   in:      none
;   out:     none
;   changes: none
        .global system
system:
        mov.w   #WDTPW|WDTHOLD, &WDTCTL             ; stop the watchdog              
        ; set unused pins low
        ; output low: clear PxOUT first, then make them outputs, so none ever drives high
        bic.b   #BIT7, &P1OUT                           ; P1.7
        bis.b   #BIT7, &P1DIR
        bic.b   #BIT6|BIT7, &P2OUT                      ; P2.6, P2.7 (XOUT/XIN, no crystal)
        bis.b   #BIT6|BIT7, &P2DIR
        bic.b   #BIT3|BIT4|BIT5|BIT6|BIT7, &P3OUT       ; P3.3-P3.7
        bis.b   #BIT3|BIT4|BIT5|BIT6|BIT7, &P3DIR
        bic.b   #BIT0|BIT1|BIT2|BIT3|BIT4, &P4OUT       ; P4.0-P4.4 (P4.4 is UCB1STE, unused)
        bis.b   #BIT0|BIT1|BIT2|BIT3|BIT4, &P4DIR
        bic.b   #BIT2|BIT3|BIT4, &P5OUT                 ; P5.2-P5.4: not on the TSSOP-38
        bis.b   #BIT2|BIT3|BIT4, &P5DIR
        clr.b   &P6OUT                                  ; P6.0-P6.6: not on the TSSOP-38
        mov.b   #0x7F, &P6DIR
        ; set up ports for the display
        bic.b   #BIT7, &P4OUT                           ; SCS low
        bis.b   #BIT7, &P4DIR
        bis.b   #BIT5|BIT6, &P4SEL0                     ; P4SEL1:0 = 01 → P4.5 = UCB1CLK, P4.6 = UCB1SIMO
        bis.b   #BIT0, &P5SEL0                          ; P5SEL1:0 = 01 → P5.0 = TB2.1...
        bic.b   #BIT1, &P5OUT                           ; display off
        bis.b   #BIT0 | BIT1, &P5DIR                    ; P5.0 (TB2.1) and P5.1 (DISP) outputs
        bic.w   #LOCKLPM5,&PM5CTL0                      ;enable io

        ; set up clocks
        bis.w   #SCG0, SR                             ;disable FLL
        nop                                           ;wait after changing status reg
        mov.w   #SELREF__REFOCLK|REFOLP, &CSCTL3      ;use REFO for reference and low power
        mov.w   #DCORSEL_3, &CSCTL1                   ;DCO range up to 8 MHz
        mov.w   #FLLD_0|243, &CSCTL2                  ;set mclk to 8Mhz
        nop
        nop 
        nop
        bic.w   #SCG0,SR                                    ;start FLL
1:      bit.w   #FLLUNLOCK0|FLLUNLOCK1, &CSCTL7             ;wait until it locks
        jnz     1b
        mov.w   #SELMS__DCOCLKDIV|SELA__REFOCLK, &CSCTL4    ;MCLK = SMCLK = DCO, ACLK = REFO
        mov.w   #TBIDEX__8, &TB0EX0                         ;set up timer B0 divide ACLK by 8 
        mov.w   #TB0_SETUP, &TB0CTL                         ;ACLK / 8 again = 512 Hz,rollover, int on wrap
        mov.w   #WDT_RUN, &WDTCTL                           ;start watchdog      
        ret

; tb0_wrap_isr: clears the interrupt flag, and wakes up main.
;   in:      none
;   out:     none
;   changes: none
tb0_wrap_isr:
        tst.w   &TB0IV                          ; reading TB0IV clears TBIFG
        bic.w   #LPM3_bits, 0(SP)               ; wake main loop
        reti