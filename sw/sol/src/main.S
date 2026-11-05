; sol: an MSP430FR2355 program in GNU assembler
; .S files go through the C preprocessor, so TI names from msp430.h work here
#include <msp430.h>
       ; .section .bss
       ; ev_que: .skip 20                ;event queue

        .text
        .global main
main:   mov.w   #WDTPW|WDTHOLD, &WDTCTL ; stop the watchdog
        bic.w   #LOCKLPM5, &PM5CTL0     ; let the port settings take effect
        bis.b   #BIT0, &P1DIR           ; P1.0 is an output
loop:   xor.b   #BIT0, &P1OUT           ; toggle P1.0
        mov.w   #50000, R12
            call    #delay                  ; in delay.S
        jmp     loop
