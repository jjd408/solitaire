; lcd.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
#include <msp430.h>
#include "sol.h"

        .section .bss
        .balign 2
        ; display buffer
        .global fb, dirty
fb:     .skip   168*18                                  ; 3024 bytes: 168 lines of 144 pixels, one bit each
        ; flags to mark which lines to send
dirty:  .skip   22                                      ; one bit per line (168 bits = 21 bytes; 22 keeps it even)

        .text

; lcd: sets up and starts spi and EXTCOMIN clock.
;   in:      none
;   out:     none
;   changes: R11,R12,R15
        .global lcd
lcd:
        mov.w   #UCSWRST, &UCB1CTLW0                    ; spi in reset while configuring
        bis.w   #SPI_SETUP, &UCB1CTLW0                  ; configure spi
        mov.w   #8, &UCB1BRW                            ; spi clock = 7.995 MHz / 8 = 999 kHz (limit 1.1 MHz)
        bic.w   #UCSWRST, &UCB1CTLW0                    ; run spi
        ; setup clock for EXTCOMIN
        mov.w   #272, &TB2CCR0                          ; up mode: 273 counts = 120 Hz at ACLK
        mov.w   #100, &TB2CCR1                          ; any value below CCR0
        mov.w   #OUTMOD_4, &TB2CCTL1                    ; toggle: TB2.1 = 60 Hz on P5.0
        mov.w   #TBSSEL__ACLK|MC__UP|TBCLR, &TB2CTL     ; start it
        ; init frame buffer
        mov     #fb, R11                                ; setup pointer
        mov     #168 * 18, R12                          ; setup counter
loop1:  mov.b   #0xFF, 0(R11)                           ; set the fb byte
        inc.w   R11
        dec     r12
        jnz     loop1
        ; init dirty flags
        mov     #dirty, R11                             ; setup pointer
        mov     #21, R12                                ; setup counter
loop2:  mov.b   #0xFF, 0(R11)                           ; set the fb byte
        inc.w   R11
        dec     r12
        jnz     loop2
call    #lcd_clear
        bis.b   #BIT1, &P5OUT 
        ret

; delay: delays in a loop, each count = .375 uS. 0 gives 65535 X.375 uS
;   in: R15 equals loop counts.
;   out:     none
;   changes: R15
delay:
        dec.w   R15
        jnz     delay
        ret

; spi_send: sends a byte to display over spi
;   in:      R12 = byte to send
;   out:     none
;   changes: none
spi_send:
1:      bit.w   #UCTXIFG, &UCB1IFG                      ; wait for tx empty
        jz      1b
        mov.b   R12, &UCB1TXBUF                         ; send it
        ret

; spi_select: turns on chip select on the display
;   in:      none
;   out:     none
;   changes: R15
spi_select:
        bis.b   #BIT7, &P4OUT                           ; chip select high
        mov.w   #22, R15
        call    #delay                                  ; wait for 6uS
        ret

; spi_deselect: turns off chip select on the display
;   in:      none
;   out:     none
;   changes: R15
spi_deselect:
1:
        bit.w   #UCBUSY, &UCB1STATW                     ; make sure it is idle
        jnz     1b
        mov.w   #8, R15
        call    #delay                                  ; wait for 2 uS
        bic.b   #BIT7, &P4OUT                           ; chip select low
        mov.w   #22, R15
        call    #delay                                  ; wait for 6 uS
        ret

; lcd_clear: clears the display.
;   in:      none
;   out:     none
;   changes: R12,R15

lcd_clear:
        call    #spi_select
        mov.b   #4, R12
        call    #spi_send
        mov.b   #0, R12
        call    #spi_send
        call    #spi_deselect
        ret

; lcd_flush: check for dirty lines and send them.
;   in:      none
;   out:     none
;   changes: R11,R12,R13,R14,R15
    .global lcd_flush
lcd_flush:
        clr.w   R13
1:      tst.b   dirty(R13)
        jnz     work                    ; something to send
        inc.w   R13
        cmp.w   #21, R13
        jne     1b
        ret                             ; all clean
work:
        call    #spi_select
        mov.b   #0x01, R12
        call    #spi_send                               ; mode: data update 
        clr.w   R13                                     ; R13 = byte number in dirty, 0-20
        clr.w   R14                                     ; R14 = line number, 0-167
next_byte:
        tst.b   dirty(R13)                              ; whole byte clean? 
        jz      skip_byte                               ;   then skip its 8 lines at once
        mov.b   #1, R15                                 ; R15 = mask: bit 0 first
next_bit:
        bit.b   R15, dirty(R13)                         ; this line dirty?
        jz      clean
        call    #send_line
clean:
        inc.w   R14                                     ; next line
        rla.b   R15                                     ; next bit: 1, 2, 4 ... 128, then 0
        jnz     next_bit                                ; 0 means all 8 bits done
        clr.b   dirty(R13)                              ; the byte's lines are sent: clear them all
        jmp     byte_done
skip_byte:
        add.w   #8, R14                                 ; 8 clean lines
byte_done:
        inc.w   R13
        cmp.w   #21, R13
        jne     next_byte
        clr.w   R12
        call    #spi_send               ; closing dummy
        call    #spi_deselect        
        ret

; send_line: sends one line to the display
;   in:      R14 line number
;   out:     none
;   changes: R11,R12
send_line:
        push.w  R10
        mov.w   R14, R12
        inc.w   R12                                     ; address = y + 1
        call    #spi_send
        mov.w   R14, R11
        rlam.w  #4, R11                                 ; y * 16
        add.w   R14, R11
        add.w   R14, R11                                ; y * 18
        add.w   #fb, R11                                ; R11 = the line's first byte in fb
        mov.w   #18, R10                                ; R10 = bytes left 
1:      mov.b   @R11+, R12                              ; next byte; R11 moves on by 1
        call    #spi_send
        dec.w   R10
        jnz     1b
        clr.w   R12
        call    #spi_send                               ; dummy
        pop.w    R10
        ret
