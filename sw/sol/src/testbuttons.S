; testbuttons.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
;
; The test screen for step 4: a box for each button, laid out as on the board, labelled over it and with how
; many events it has given under it (in the 3 x 5 font). The button of the latest event is drawn filled.
;
;   BUTTON TEST
;          S1    S2    S3    S4                    suits: roles B_FOUND1-4
;          []    []    []    []
;   1   2   3   4   5   6   7                      stacks: roles B_TABLEAU1-7
;   []  []  []  []  []  []  []
;   STOCK WASTE  NEW  UNDO OPTIONS                 bottom row: roles B_STOCK, B_WASTE, B_NEW, B_UNDO, B_OPTIONS
;    []    []    []    []    []
;   EVENTS n
; The rows are as on the board, top to bottom, each centred; the suits and the bottom row are spaced wider
; than the stacks, as there.
#include <msp430.h>
#include "sol.h"

#define BOX       14            /* pixels square */
#define WIDE      28            /* box to box in the suits and bottom rows */
#define NARROW    20            /* box to box in the stacks row */
#define ROW1_Y    26            /* the rows' boxes, top */
#define ROW2_Y    70
#define ROW3_Y    114
#define LABEL_DY  -7            /* the label, this far below the box's top (above it) */
#define COUNT_DY  17            /* the count, this far below the box's top */
#define TOTAL_Y   152
#define MAX_COUNT 99            /* counts stop here, to fit under a box */

        .section .bss
        .global presses
presses: .skip  B_ROLES                                 ; events counted, by role (presses[0] unused)
last:   .skip   1                                       ; the role of the latest event, or 0
        .balign 2
        .global total
total:  .skip   2                                       ; all events

        .section .rodata
; Where each role's box is, by role: x and y of its top left (role 0 unused). Each row is centred on the screen.
#define SUIT_X(n)   ((LCD_W - 3 * WIDE - BOX) / 2 + WIDE * (n))
#define STACK_X(n)  ((LCD_W - 6 * NARROW - BOX) / 2 + NARROW * (n))
#define BOTTOM_X(n) ((LCD_W - 4 * WIDE - BOX) / 2 + WIDE * (n))
box_x:  .byte   0
        .byte   STACK_X(0), STACK_X(1), STACK_X(2), STACK_X(3), STACK_X(4), STACK_X(5), STACK_X(6) ; tableau 1-7
        .byte   BOTTOM_X(1), BOTTOM_X(0)                ; B_WASTE, B_STOCK: stock first in the bottom row
        .byte   SUIT_X(0), SUIT_X(1), SUIT_X(2), SUIT_X(3) ; B_FOUND1-4
        .byte   BOTTOM_X(2), BOTTOM_X(3), BOTTOM_X(4)   ; B_NEW, B_UNDO, B_OPTIONS: after stock and waste
box_y:  .byte   0
        .byte   ROW2_Y, ROW2_Y, ROW2_Y, ROW2_Y, ROW2_Y, ROW2_Y, ROW2_Y
        .byte   ROW3_Y, ROW3_Y
        .byte   ROW1_Y, ROW1_Y, ROW1_Y, ROW1_Y
        .byte   ROW3_Y, ROW3_Y, ROW3_Y
; Each role's label, by role
        .balign 2
box_label:
        .word   0
        .word   l_1, l_2, l_3, l_4, l_5, l_6, l_7
        .word   l_waste, l_stock
        .word   l_s1, l_s2, l_s3, l_s4
        .word   l_new, l_undo, l_options
l_1:    .asciz  "1"
l_2:    .asciz  "2"
l_3:    .asciz  "3"
l_4:    .asciz  "4"
l_5:    .asciz  "5"
l_6:    .asciz  "6"
l_7:    .asciz  "7"
l_waste: .asciz "WASTE"
l_stock: .asciz "STOCK"
l_s1:   .asciz  "S1"
l_s2:   .asciz  "S2"
l_s3:   .asciz  "S3"
l_s4:   .asciz  "S4"
l_new:  .asciz  "NEW"
l_undo: .asciz  "UNDO"
l_options: .asciz "OPTIONS"
title:  .asciz  "BUTTON TEST"
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
        mov.w   #1, R10                                 ; every button's box, roles 1-16
1:      mov.w   R10, R12
        call    #draw_label
        mov.w   R10, R12
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

; draw_label: writes a role's label over its box, centred on it, in the small font.
;   in:      R12 = the role, 1 to B_ROLES - 1
;   out:     none
;   changes: R11-R15
draw_label:
        push.w  R10
        mov.w   R12, R10                                ; R10 = the role
        rla.w   R12
        mov.w   box_label(R12), R12
        push.w  R12                                     ; the label, for gfx_text_small below
        call    #gfx_text_width_small                   ; R12 = its width
        mov.w   #BOX, R14
        sub.w   R12, R14
        rra.w   R14                                     ; (box - width) / 2: negative if wider than the box
        mov.b   box_x(R10), R12
        add.w   R14, R12                                ; x, centred on the box
        mov.b   box_y(R10), R13
        add.w   #LABEL_DY, R13
        pop.w   R14
        call    #gfx_text_small
        pop.w   R10
        ret

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
1:      mov.w   R8, R12                                 ; the count: clear its place...
        mov.w   R9, R13
        add.w   #COUNT_DY, R13
        mov.w   #BOX, R14
        mov.w   #5, R15
        call    #gfx_white
        mov.w   R8, R12                                 ; ...and write it centred under the box:
        add.w   #(BOX - 3) / 2, R12                     ;    one digit is 3 pixels wide...
        cmp.b   #10, presses(R10)
        jlo     2f
        sub.w   #2, R12                                 ;    ...two are 7
2:      mov.w   R9, R13
        add.w   #COUNT_DY, R13
        mov.b   presses(R10), R14
        call    #gfx_number_small
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
