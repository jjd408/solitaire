; testbuttons.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
;
; The test screen for step 4: a box for each button, laid out as on the board, with how many events it has
; given under it. The button of the latest event is drawn filled.
;
;   BUTTON TEST
;   SW1-SW3          [] [] []                      roles B_NEW, B_UNDO, B_OPTIONS
;   STACKS 1-9       [] [] [] [] [] [] [] [] []    roles B_TABLEAU1-7, B_WASTE, B_STOCK
;   SUITS 1-4        [] [] [] []                   roles B_FOUND1-4
;   EVENTS n
#include <msp430.h>
#include "sol.h"

#define BOX      14             /* pixels square */
#define PITCH    16             /* from one box to the next */
#define ROW1_Y   30
#define ROW2_Y   72
#define ROW3_Y   114
#define COUNT_DY 16             /* the count, this far below the box's top */
#define TOTAL_Y  150
#define MAX_COUNT 99            /* counts stop here, to fit under a box */

        .section .bss
        .global presses
presses: .skip  B_ROLES                                 ; events counted, by role (presses[0] unused)
last:   .skip   1                                       ; the role of the latest event, or 0
        .balign 2
        .global total
total:  .skip   2                                       ; all events

        .section .rodata
; Where each role's box is, by role: x and y of its top left (role 0 unused)
#define X(col) (1 + PITCH * (col))
box_x:  .byte   0
        .byte   X(0), X(1), X(2), X(3), X(4), X(5), X(6) ; B_TABLEAU1-7: stacks 1-7
        .byte   X(7), X(8)                              ; B_WASTE, B_STOCK: stacks 8, 9
        .byte   X(0), X(1), X(2), X(3)                  ; B_FOUND1-4: suits 1-4
        .byte   X(0), X(1), X(2)                        ; B_NEW, B_UNDO, B_OPTIONS: SW1-SW3
box_y:  .byte   0
        .byte   ROW2_Y, ROW2_Y, ROW2_Y, ROW2_Y, ROW2_Y, ROW2_Y, ROW2_Y
        .byte   ROW2_Y, ROW2_Y
        .byte   ROW3_Y, ROW3_Y, ROW3_Y, ROW3_Y
        .byte   ROW1_Y, ROW1_Y, ROW1_Y
title:  .asciz  "BUTTON TEST"
row1:   .asciz  "SW1-SW3"
row2:   .asciz  "STACKS 1-9"
row3:   .asciz  "SUITS 1-4"
events_text:
        .asciz  "EVENTS "

        .text

; button_screen: draws the whole test screen, all counts 0. Call lcd_flush to show it.
;   in:      none
;   out:     none
;   changes: R11-R15
        .global button_screen
button_screen:
        push.w  R10
        call    #gfx_clear
        mov.w   #2, R12
        mov.w   #4, R13
        mov.w   #title, R14
        call    #gfx_text
        mov.w   #2, R12
        mov.w   #ROW1_Y-10, R13
        mov.w   #row1, R14
        call    #gfx_text
        mov.w   #2, R12
        mov.w   #ROW2_Y-10, R13
        mov.w   #row2, R14
        call    #gfx_text
        mov.w   #2, R12
        mov.w   #ROW3_Y-10, R13
        mov.w   #row3, R14
        call    #gfx_text
        mov.w   #1, R10                                 ; every button's box, roles 1-16
1:      mov.w   R10, R12
        call    #draw_box
        inc.w   R10
        cmp.w   #B_ROLES, R10
        jne     1b
        call    #draw_total
        pop.w   R10
        ret

; button_event: counts an event and redraws what it changed: its box (filled now), the box of the event before
; (no longer filled) and the total.
;   in:      R12 = the role (B_NONE or anything past the last role is ignored)
;   out:     none
;   changes: R11-R15
        .global button_event
button_event:
        tst.w   R12
        jz      2f
        cmp.w   #B_ROLES, R12
        jhs     2f
        push.w  R10
        mov.w   R12, R10                                ; R10 = the role
        cmp.b   #MAX_COUNT, presses(R10)
        jhs     1f
        inc.b   presses(R10)
1:      inc.w   &total
        mov.b   &last, R12                              ; the box filled until now
        mov.b   R10, &last
        tst.w   R12
        jz      3f
        call    #draw_box                               ; drawn again, now empty
3:      mov.w   R10, R12
        call    #draw_box                               ; this one, filled
        call    #draw_total
        pop.w   R10
2:      ret

; draw_box: draws a role's box (filled if it's the latest event's) and its count under it.
;   in:      R12 = the role, 1 to B_ROLES - 1
;   out:     none
;   changes: R11-R15
draw_box:
        pushm.w #3, R10                                 ; R8-R10
        mov.w   R12, R10                                ; R10 = the role
        mov.b   box_x(R10), R8                          ; R8 = x
        mov.b   box_y(R10), R9                          ; R9 = y
        mov.w   R8, R12                                 ; the box: black square...
        mov.w   R9, R13
        mov.w   #BOX, R14
        mov.w   #BOX, R15
        call    #gfx_black
        cmp.b   &last, R10
        jeq     1f                                      ; ...left filled for the latest event
        mov.w   R8, R12                                 ; ...else white inside, leaving the outline
        inc.w   R12
        mov.w   R9, R13
        inc.w   R13
        mov.w   #BOX-2, R14
        mov.w   #BOX-2, R15
        call    #gfx_white
1:      mov.w   R8, R12                                 ; the count: clear its place, then write it
        mov.w   R9, R13
        add.w   #COUNT_DY, R13
        mov.w   #PITCH, R14
        mov.w   #7, R15
        call    #gfx_white
        mov.w   R8, R12
        inc.w   R12
        mov.w   R9, R13
        add.w   #COUNT_DY, R13
        mov.b   presses(R10), R14
        call    #gfx_number
        popm.w  #3, R10
        ret

; draw_total: writes "EVENTS n" at the bottom.
;   in:      none
;   out:     none
;   changes: R11-R15
draw_total:
        mov.w   #0, R12
        mov.w   #TOTAL_Y, R13
        mov.w   #LCD_W, R14
        mov.w   #7, R15
        call    #gfx_white
        mov.w   #2, R12
        mov.w   #TOTAL_Y, R13
        mov.w   #events_text, R14
        call    #gfx_text                               ; R12 = x after it
        mov.w   #TOTAL_Y, R13
        mov.w   &total, R14
        call    #gfx_number
        ret
