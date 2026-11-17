; main.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
#include <msp430.h>
#include "sol.h"

/* What to build: 0 the game; or a test screen: 1 the step 2 pattern, 2 the step 3 card sheet, 3 the step 4
   button screen, 4 the step 7 squeeze (a made-up game, then the game as usual). The tests choose with
   -DTEST_SCREEN=n; NetBeans builds the game. */
#ifndef TEST_SCREEN
#define TEST_SCREEN 0
#endif

        .text

; main: sets everything up, then waits for events and handles each one. Never returns.
;   in:      none
;   out:     none
;   changes: none
        .global main
main:
        call    #system                                 ; init clocks and io ports
        call    #lcd                                    ; init display
        call    #buttons                                ; init buttons io
#if TEST_SCREEN == 0
        call    #ui_start                               ; the game kept in FRAM, or the title screen
#elif TEST_SCREEN == 1
        call    #test_pattern                           ; step 2's test picture
#elif TEST_SCREEN == 2
        call    #card_sheet                             ; step 3's sheet of cards
#elif TEST_SCREEN == 3
        call    #button_screen                          ; step 4's button test screen
#elif TEST_SCREEN == 4
        call    #squeeze_screen                         ; step 7's squeeze test: a made-up game
#endif
loop:
        mov.w   #WDT_RUN, &WDTCTL                       ; kick the watchdog
        call    #lcd_flush                              ; update display
        dint                                            ; no interrupts while deciding to sleep
        nop
        call    #q_check                                ; anything in the queue?
        tst.b   R12
        jnz     1f                                      ; yes: handle it
        bis     #LPM3_bits|GIE, SR                      ; no: sleep, enabling interrupts in the same instruction
        nop
1:      eint                                            ; awake (or never slept): interrupts on
        nop
        call    #q_pop                                  ; R12 = the next event's role, or 0
        tst.w   R12
        jz      loop                                    ; none (a timer wake-up): back round
#if TEST_SCREEN == 0 || TEST_SCREEN == 4
        call    #ui_button                              ; the game does what the button means
#elif TEST_SCREEN == 3
        call    #button_event                           ; the button test screen counts it
#endif
        jmp     loop                                    ; for the next event

