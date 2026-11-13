#define WDT_RUN (WDTPW|WDTSSEL__ACLK|WDTIS__8192K|WDTCNTCL)   /* watchdog on ACLK, 256 s, kick */
#define TB0_SETUP (TBSSEL__ACLK|ID__8|MC__CONTINUOUS|TBCLR|TBIE)
#define SPI_SETUP (UCCKPH|UCMST|UCSYNC|UCSSEL__SMCLK)

/* The display */
#define LCD_W   144             /* pixels across */
#define LCD_H   168             /* lines */
#define LINE    18              /* bytes per line in fb */

/* Cards: a card is one byte (see PLAN.md, Game): bits 0-3 rank 1-13, bits 4-5 suit, bit 7 face up */
#define RANK_MASK  0x0F
#define SUIT_MASK  0x30
#define SPADES     0x00
#define CLUBS      0x10
#define HEARTS     0x20         /* bit 5 set: red */
#define DIAMONDS   0x30
#define FACE_UP    0x80
#define SELECTED   0x40         /* only in what's passed to gfx_card: draw it inverted */
#define CARD_W     19           /* pixels */
#define CARD_H     26

/* Button roles: what an event means, whichever pin it came from (buttons.S maps pins to roles) */
#define B_NONE      0           /* no event: the queue is empty */
#define B_TABLEAU1  1           /* tableau columns 1-7, left to right: B_TABLEAU1 + n - 1 for column n */
#define B_TABLEAU2  2
#define B_TABLEAU3  3
#define B_TABLEAU4  4
#define B_TABLEAU5  5
#define B_TABLEAU6  6
#define B_TABLEAU7  7
#define B_WASTE     8           /* the waste pile: a source for a move */
#define B_STOCK     9           /* deal to the waste, or turn the waste over when the stock is empty */
#define B_FOUND1    10          /* foundations 1-4: B_FOUND1 + n - 1 for foundation n */
#define B_FOUND2    11
#define B_FOUND3    12
#define B_FOUND4    13
#define B_NEW       14          /* new game (press twice to confirm) */
#define B_UNDO      15          /* undo the last move */
#define B_OPTIONS   16          /* open or close the options screen */
#define B_ROLES     17          /* how many role numbers there are, counting B_NONE: sizes tables by role */

