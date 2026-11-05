; MSP430FR2355 assembly (GNU as, msp430-elf-as)
#include <msp430.h>
      
        .text
        .global sysinit
sysinit:   mov.w   #WDTPW|WDTHOLD, &WDTCTL ; stop the watchdog

