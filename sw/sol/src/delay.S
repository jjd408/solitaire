; delay: waits about R12 x 3 cycles
; A routine in a file of its own, linked with main.S into one program
#include <msp430.h>

        .text
        .global delay
delay:  dec.w   R12
        jnz     delay
        ret
