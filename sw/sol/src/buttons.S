; buttons.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
#include <msp430.h>
#include "sol.h"
        .section .bss
events: .skip   16                                      ; the event queue: a ring of 16 roles
head:   .skip   1                                       ; the next event to take (main)
tail:   .skip   1                                       ; the next free slot (the port interrupts)
p1_locked: .skip 1                                      ; pins locked after a press, one bit each
p2_locked: .skip 1
p3_locked: .skip 1
p1_seen: .skip  1                                       ; locked pins that read released on the last tick
p2_seen: .skip  1
p3_seen: .skip  1

        .section __interrupt_vector_timer0_b0, "ax", @progbits ; TB0 CCR0: the debounce tick
        .word   timer0_b0_isr
        .section __interrupt_vector_port1, "ax", @progbits ; P1 interrupts
        .word   p1_isr
        .section __interrupt_vector_port2, "ax", @progbits ; P2 interrupts
        .word   p2_isr
        .section __interrupt_vector_port3, "ax", @progbits ; P3 interrupts
        .word   p3_isr

        .section .rodata
p1_roles:                                               ; the role of each pin, P1.0 ... P1.7
        .byte   B_TABLEAU1, B_TABLEAU2, B_TABLEAU3, B_TABLEAU4
        .byte   B_TABLEAU5, B_TABLEAU6, B_TABLEAU7, B_NONE
p2_roles:                                               ; P2.0 ... P2.7
        .byte   B_WASTE, B_STOCK, B_FOUND1, B_FOUND2
        .byte   B_FOUND3, B_FOUND4, B_NONE, B_NONE
p3_roles:                                               ; P3.0 ... P3.7
        .byte   B_NEW, B_UNDO, B_OPTIONS, B_NONE
        .byte   B_NONE, B_NONE, B_NONE, B_NONE
pin_mask:                                               ; the mask of bit 0 ... bit 7, for any port
        .byte   BIT0, BIT1, BIT2, BIT3, BIT4, BIT5, BIT6, BIT7

        .text
; buttons: enables the buttons' interrupts and empties the queue. The pins are set up in system.
;   in:      none
;   out:     none
;   changes: none
        .global buttons
buttons:
        clr.b   &P1IFG                                  ; forget flags set at start-up
        clr.b   &P2IFG
        clr.b   &P3IFG
        bis.b   #0x7F, &P1IE                            ; enable interrupts
        bis.b   #0x3F, &P2IE
        bis.b   #0x07, &P3IE
        mov.b   #0, &head                               ; empty the queue
        mov.b   #0, &tail
        ret

; q_push: adds an event to the queue; drops it if the queue is full.
;   in:      R12 = the role
;   out:     none
;   changes: R13, R14
        .global q_push
q_push:
        mov.b   &tail, R13                              ; R13 = tail
        mov.w   R13, R14
        inc.w   R14
        and.w   #15, R14                                ; R14 = tail + 1, wrapped
        cmp.b   &head, R14
        jeq     1f                                      ; tail + 1 == head: full, drop it
        mov.b   R12, events(R13)                        ; store the event first...
        mov.b   R14, &tail                              ; ...then move tail: now main can see it
1:      ret

; q_pop: takes the next event from the queue.
;   in:      none
;   out:     R12 = the role, or B_NONE (0) if the queue is empty
;   changes: R12, R13
        .global q_pop
q_pop:
        clr.w   R12
        mov.b   &head, R13                              ; R13 = head
        cmp.b   &tail, R13
        jeq     1f                                      ; head == tail: empty, return 0
        mov.b   events(R13), R12                        ; read the event first...
        inc.w   R13
        and.w   #15, R13
        mov.b   R13, &head                              ; ...then move head: the slot is free again
1:      ret

; q_check: whether the queue has anything, without taking it (for main's check before sleeping).
;   in:      none
;   out:     R12 = 0 if empty, else non-zero
;   changes: R12
        .global q_check
q_check:
        mov.b   &tail, R12
        sub.b   &head, R12                              ; 0 only if head == tail (sub.b keeps it to a byte)
        ret

; tick_start: makes TB0 CCR0 interrupt 15 counts (29 ms) from now, unless it's already ticking.
;   in:      none
;   out:     none
;   changes: R13
tick_start:
        bit.w   #CCIE, &TB0CCTL0                        ; already ticking?
        jnz     2f                                      ; then leave it
1:      mov.w   &TB0R, R13                              ; read the count...
        cmp.w   &TB0R, R13                              ; ...twice: TB0 runs on ACLK, not the CPU's clock,
        jne     1b                                      ;    so a read mid-change can be wrong; repeat until two agree
        add.w   #15, R13                                ; 15 counts on: 15 / 512 Hz = 29.3 ms
        mov.w   R13, &TB0CCR0
        bic.w   #CCIFG, &TB0CCTL0                       ; forget any old match
        bis.w   #CCIE, &TB0CCTL0                        ; interrupt when TB0R reaches TB0CCR0
2:      ret

; timer0_b0_isr: the debounce tick, every 29 ms while any button is locked. A locked pin is unlocked once it
; has read released on two ticks in a row; then the tick goes on if anything is still locked, or stops.
;   changes: nothing (an interrupt saves all it uses)
timer0_b0_isr:
        pushm.w #3, R15                                 ; save R13-R15

        mov.b   &P1IN, R13                              ; port 1:
        and.b   &p1_locked, R13                         ; R13 = locked pins that read released (1) now
        mov.b   R13, R14
        and.b   &p1_seen, R14                           ; R14 = released now and on the last tick: unlock them
        bic.b   R14, R13                                ; R13 = released now for the first time
        bic.b   R14, &P1IFG                             ; forget edges from while they were locked
        bis.b   R14, &P1IE                              ; and let them interrupt again
        bic.b   R14, &p1_locked                         ; no longer locked
        mov.b   R13, &p1_seen                           ; remember the first-time ones for the next tick

        mov.b   &P2IN, R13                              ; port 2:
        and.b   &p2_locked, R13                         ; R13 = locked pins that read released (1) now
        mov.b   R13, R14
        and.b   &p2_seen, R14                           ; R14 = released now and on the last tick: unlock them
        bic.b   R14, R13                                ; R13 = released now for the first time
        bic.b   R14, &P2IFG                             ; forget edges from while they were locked
        bis.b   R14, &P2IE                              ; and let them interrupt again
        bic.b   R14, &p2_locked                         ; no longer locked
        mov.b   R13, &p2_seen                           ; remember the first-time ones for the next tick

        mov.b   &P3IN, R13                              ; port 3:
        and.b   &p3_locked, R13                         ; R13 = locked pins that read released (1) now
        mov.b   R13, R14
        and.b   &p3_seen, R14                           ; R14 = released now and on the last tick: unlock them
        bic.b   R14, R13                                ; R13 = released now for the first time
        bic.b   R14, &P3IFG                             ; forget edges from while they were locked
        bis.b   R14, &P3IE                              ; and let them interrupt again
        bic.b   R14, &p3_locked                         ; no longer locked
        mov.b   R13, &p3_seen                           ; remember the first-time ones for the next tick

        mov.b   &p1_locked, R15                         ; anything still locked, on any port?
        bis.b   &p2_locked, R15
        bis.b   &p3_locked, R15
        tst.b   R15                                     ; (bis doesn't set the flags)
        jz      1f
        add.w   #15, &TB0CCR0                           ; some still locked: tick again 29 ms after this one
        jmp     2f
1:      bic.w   #CCIE, &TB0CCTL0                        ; nothing locked: stop ticking
2:      popm.w  #3, R15                                 ; restore R13-R15
        reti


; p1_isr: a press on port 1: queues each pressed pin's role, locks the pin (its interrupt off) and
; starts the debounce tick; wakes main.
;   changes: nothing (an interrupt saves all it uses)
p1_isr:
        pushm.w #4, R15                                 ; save R12-R15
1:      mov.w   &P1IV, R13                              ; the next pending pin, 2 x (bit + 1), or 0; clears its flag
        tst.w   R13
        jz      2f
        rra.w   R13                                     ; R13 = bit + 1, 1-8
        mov.b   p1_roles-1(R13), R12                    ; its role (the table starts at bit 0, hence -1)
        mov.b   pin_mask-1(R13), R15                    ; its mask (q_push doesn't change R15)
        call    #q_push                                 ; queue the role
        bic.b   R15, &P1IE                              ; lock the pin: its interrupt off, so bounces are ignored
        call    #tick_start                             ; start the debounce tick, if it isn't running
        bis.b   R15, &p1_locked
        jmp     1b                                      ; check for more
2:      bic.w   #LPM3_bits, 8(SP)                       ; wake main: SR is above the 4 saved words
        popm.w  #4, R15                                 ; restore R12-R15
        reti

; p2_isr: a press on port 2: queues each pressed pin's role, locks the pin (its interrupt off) and
; starts the debounce tick; wakes main.
;   changes: nothing (an interrupt saves all it uses)
p2_isr:
        pushm.w #4, R15                                 ; save R12-R15
1:      mov.w   &P2IV, R13                              ; the next pending pin, 2 x (bit + 1), or 0; clears its flag
        tst.w   R13
        jz      2f
        rra.w   R13                                     ; R13 = bit + 1, 1-8
        mov.b   p2_roles-1(R13), R12                    ; its role (the table starts at bit 0, hence -1)
        mov.b   pin_mask-1(R13), R15                    ; its mask (q_push doesn't change R15)
        call    #q_push                                 ; queue the role
        bic.b   R15, &P2IE                              ; lock the pin: its interrupt off, so bounces are ignored
        call    #tick_start                             ; start the debounce tick, if it isn't running
        bis.b   R15, &p2_locked
        jmp     1b                                      ; check for more
2:      bic.w   #LPM3_bits, 8(SP)                       ; wake main: SR is above the 4 saved words
        popm.w  #4, R15                                 ; restore R12-R15
        reti


; p3_isr: a press on port 3: queues each pressed pin's role, locks the pin (its interrupt off) and
; starts the debounce tick; wakes main.
;   changes: nothing (an interrupt saves all it uses)
p3_isr:
        pushm.w #4, R15                                 ; save R12-R15
1:      mov.w   &P3IV, R13                              ; the next pending pin, 2 x (bit + 1), or 0; clears its flag
        tst.w   R13
        jz      2f
        rra.w   R13                                     ; R13 = bit + 1, 1-8
        mov.b   p3_roles-1(R13), R12                    ; its role (the table starts at bit 0, hence -1)
        mov.b   pin_mask-1(R13), R15                    ; its mask (q_push doesn't change R15)
        call    #q_push                                 ; queue the role
        bic.b   R15, &P3IE                              ; lock the pin: its interrupt off, so bounces are ignored
        call    #tick_start                             ; start the debounce tick, if it isn't running
        bis.b   R15, &p3_locked
        jmp     1b                                      ; check for more
2:      bic.w   #LPM3_bits, 8(SP)                       ; wake main: SR is above the 4 saved words
        popm.w  #4, R15                                 ; restore R12-R15
        reti

