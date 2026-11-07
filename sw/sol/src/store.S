; store.S: MSP430FR2355 assembly (GNU as)
; .S files go through the C preprocessor, so TI's names from msp430.h work here.
#include <msp430.h>

        .text

; store: (what it does)
;   in:      (arguments: R12, R13, R14, R15)
;   out:     (result: R12)
;   changes: (R11-R15 may be changed; save R4-R10 if used)
        .global store
store:
        ret
