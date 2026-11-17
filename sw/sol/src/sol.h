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

/* Piles (STEP5-game.md): numbers for pile_count, pile_top, pile_card, pile_push, pile_pop */
#define P_STOCK     0
#define P_WASTE     1
#define P_FOUND1    2           /* foundations 1-4: P_FOUND1 + n - 1 */
#define P_TAB1      6           /* tableau columns 1-7: P_TAB1 + n - 1 (= role B_TABLEAU1 + 5) */
#define P_PILES     13          /* how many */
#define P_SCRATCH   13          /* pile_move's scratch pile, in RAM: not one of the game's 13 */
#define GAME_MAGIC  0x50CA      /* in game_magic once a game has been dealt */
#define STORE_VERSION 2         /* the layout of the saved game (store.S): a game saved with another is dropped */
#define SETTINGS_MAGIC 0x5E77   /* in settings_magic while the settings and statistics are valid */
#define UNDO_SIZE   256         /* records in the undo log (a ring: the oldest are forgotten) */

/* Layout (PLAN.md, Layout): columns 20 pixels apart, the top row at y 2, the tableau from y 30 */
#define COL_X(n)    (2 + 20 * (n))
#define TOP_Y       2
#define TABLE_Y     30
#define STRIP_DOWN  3           /* lines a face-down card shows when another covers it */
#define STRIP_UP    10          /* lines a face-up card shows when another covers it */
#define STATUS_Y    161         /* the status line, in the small font */
#define STATUS_TOP  159         /* the status line's band: lines 159-167 (a message shows inverted across it) */
#define TABLE_H     128         /* lines for the tableau: y 30-157 (PLAN.md, Layout) */
#define STRIP_DOWN_MIN 1        /* a squeezed column's strips (PLAN.md, Layout): face down from 3 to 1... */
#define STRIP_UP_MIN 8          /* ...then face up from 10 to 8 */
#define WASTE_FAN   9           /* draw 3: the waste's top three cards, 9 pixels apart */

/* What ui_update redraws (ui.S's redraw word): a bit per pile (1 << pile), and these */
#define R_STATUS    0x2000      /* the status line */
#define R_ALL       0x4000      /* everything: the table and the status line, or the title or options screen */

/* Which screen the buttons work on (ui.S's mode) */
#define MODE_TABLE  0           /* the game (or the title screen, before there is one) */
#define MODE_OPTIONS 1          /* the options screen */

/* The move record (STEP6-moves.md): 4 bytes, enough to undo the move exactly */
#define M_SOURCE    0           /* byte offsets: the pile the cards came from */
#define M_DEST      1           /* the pile they went to */
#define M_COUNT     2           /* how many cards moved */
#define M_FLAGS     3           /* what else happened: */
#define M_TURNED    1           /*   the source's new top card was turned face up */
#define M_RECYCLED  2           /*   the waste was turned back over into the stock */

/* Scoring (PLAN.md, Options) */
#define S_OFF       0           /* the move count only */
#define S_STANDARD  1           /* +5 waste to tableau, +10 to a foundation, +5 a turn-over, -15 off a foundation */
#define S_VEGAS     2           /* -52 to start, +5 a card to a foundation, -5 a card off one */
#define VEGAS_START -52

/* What game_stock says */
#define STOCK_NONE  0           /* nothing to do: the stock and the waste are empty */
#define STOCK_DONE  1           /* dealt, or turned the waste over */
#define STOCK_LIMIT 2           /* the waste can't be turned over: no passes left */

