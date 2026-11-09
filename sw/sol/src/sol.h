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
