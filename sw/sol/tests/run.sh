#!/bin/sh
# Automated tests for the solitaire firmware, on the simulator (see sw/PLAN.md, Testing).
#
# Builds the firmware from sw/sol/src, runs it on msp430_run with the display model connected, and checks each
# scenario: the display's report (no timing problems, EXTCOMIN 57-66 Hz, display on) and the screen against an
# approved picture, NAME.pbm in this folder.
#
#   tests/run.sh            run every test
#
# Button tests also check how many events each button gave (read from memory) and that the chip ended asleep.
#
# A screen that doesn't match is saved as NAME.new.pbm beside the approved one, to look at. If the change was
# meant, approve it by renaming NAME.new.pbm to NAME.pbm (and committing it). A test with no approved picture yet
# saves NAME.new.pbm the same way.
#
# Finds the toolchain in $MSP430_GCC_BIN, ~/ti/msp430-gcc*/bin or on the PATH, and the runner in $MSP430_RUN or
# the simulator checkout (build it with the simulator's tests/run_tests.sh).
set -u

here=$(cd "$(dirname "$0")" && pwd)
sol=$(dirname "$here")
repo=$(cd "$sol/../.." && pwd)
out=$here/out
mkdir -p "$out"

# The toolchain
bin=${MSP430_GCC_BIN:-}
if [ -z "$bin" ]; then
    for d in "$HOME"/ti/msp430-gcc*/bin; do
        [ -x "$d/msp430-elf-gcc" ] && bin=$d
    done
fi
if [ -n "$bin" ]; then
    gcc=$bin/msp430-elf-gcc
    objcopy=$bin/msp430-elf-objcopy
    nm=$bin/msp430-elf-nm
    inc=$(dirname "$bin")/include
else
    gcc=msp430-elf-gcc
    objcopy=msp430-elf-objcopy
    nm=msp430-elf-nm
    inc=
fi
if ! command -v "$gcc" >/dev/null 2>&1; then
    echo "msp430-elf-gcc not found: set MSP430_GCC_BIN to the toolchain's bin folder" >&2
    exit 2
fi

# The runner
run=${MSP430_RUN:-$repo/sim/picsimlab-msp430/src/sim_backend/msp430/tests/msp430_run}
if [ ! -x "$run" ]; then
    echo "msp430_run not found at $run: build it with the simulator's tests/run_tests.sh, or set MSP430_RUN" >&2
    exit 2
fi

# build NAME [gcc options...]: builds the firmware the way the NetBeans project does, with extra options such as
# -DTEST_SCREEN=1, into out/NAME.hex
build() {
    name=$1
    shift
    if ! "$gcc" -mmcu=msp430fr2355 -g ${inc:+-I"$inc" -L"$inc"} -I"$sol/src" "$@" "$sol"/src/*.S \
            -o "$out/$name.elf" || ! "$objcopy" -O ihex "$out/$name.elf" "$out/$name.hex"; then
        echo "FAIL: the firmware doesn't build ($name)" >&2
        exit 1
    fi
}

# The display's pins by package pin number: SCLK, SI, SCS, EXTCOMIN, DISP
SHARP=18,17,16,37,36

passed=0
failed=0

pass() {
    echo "PASS: $1"
    passed=$((passed + 1))
}

fail() {
    echo "FAIL: $1"
    failed=$((failed + 1))
}

# screen NAME BUILD SECONDS [runner options...]: runs out/BUILD.hex for SECONDS of simulated time and checks the
# display, against the approved picture NAME.pbm
screen() {
    name=$1
    hex=$out/$2.hex
    seconds=$3
    shift 3
    got=$out/$name.pbm
    rm -f "$got"
    report=$("$run" "$hex" --seconds "$seconds" --tick 8e6 --sharp "$SHARP,$got" "$@" 2>&1)
    sharp=$(echo "$report" | grep '^sharp:')
    problems=

    if [ -z "$sharp" ] || [ ! -f "$got" ]; then
        fail "$name: no report from the display model"
        echo "$report" | sed 's/^/    /'
        return
    fi
    case $sharp in
        *"no timing problems"*) ;;
        *) problems="$problems; timing" ;;
    esac
    hz=$(echo "$sharp" | sed -n 's/.*EXTCOMIN \([0-9]*\) Hz.*/\1/p')
    if [ -z "$hz" ] || [ "$hz" -lt 57 ] || [ "$hz" -gt 66 ]; then
        problems="$problems; EXTCOMIN ${hz:-?} Hz (57-66)"
    fi
    case $sharp in
        *"DISP 1"*) ;;
        *) problems="$problems; the display is off (DISP 0)" ;;
    esac

    against=${APPROVED:-$name}                          # APPROVED=OTHER: compare with OTHER.pbm instead
    APPROVED=                                           # (some shells keep it after the call: just this once)
    approved=$here/$against.pbm
    new=$here/$name.new.pbm
    if [ ! -f "$approved" ]; then
        cp "$got" "$new"
        problems="$problems; no approved picture yet: look at tests/$name.new.pbm and, if it's right, rename it"
        problems="$problems to $against.pbm"
    elif ! cmp -s "$got" "$approved"; then
        cp "$got" "$new"
        problems="$problems; the screen differs from tests/$against.pbm: see tests/$name.new.pbm"
    else
        rm -f "$new"
    fi

    if [ -z "$problems" ]; then
        pass "$name"
    else
        fail "$name: ${problems#; }"
        echo "    $sharp"
    fi
}

# counts NAME BUILD EXPECTED: after screen, checks the events counted by role (the button test screen's presses
# array, 0 to 16, from the --peek the screen run was given) and that the chip ended asleep in LPM3
counts() {
    name=$1
    addr=$("$nm" "$out/$2.elf" | awk '$3 == "presses" { print toupper(substr($1, length($1) - 3)) }')
    words=$(echo "$report" | grep "^$addr:" | cut -d: -f2)
    got=$(for w in $words; do printf '%d %d ' $((0x$w & 0xFF)) $((0x$w >> 8)); done |
        awk '{ for (i = 1; i <= 17; i++) printf "%s%s", $i, (i < 17 ? " " : "") }')
    sr=$(echo "$report" | sed -n 's/.* SR=\([0-9A-Fa-f]*\) .*/\1/p')
    if [ "$got" != "$3" ]; then
        fail "$name counts: events by role (0-16) were $got, not $3"
    elif [ -z "$sr" ] || [ $((0x$sr & 0xD0)) -ne $((0xD0)) ]; then
        fail "$name counts: not asleep in LPM3 at the end (SR=$sr)"
    else
        pass "$name counts"
    fi
}

# deal NAME BUILD SEED DEALS: checks the game in FRAM, from the --peek of the last run (screen or run_only),
# against tests/deal.py's reference deal for that seed, and that DEALS games have been dealt
deal() {
    name=$1
    addr=$("$nm" "$out/$2.elf" | awk '$3 == "game_magic" { print toupper(substr($1, length($1) - 3)) }')
    if result=$(echo "$report" | python3 "$here/deal.py" "$addr" "$3" "$4"); then
        pass "$name piles"
    else
        fail "$name piles: $(echo "$result" | head -3 | tr '\n' ' ')"
    fi
}

# run_only BUILD SECONDS [runner options...]: runs without the display model, for a deal check
run_only() {
    hex=$out/$1.hex
    seconds=$2
    shift 2
    report=$("$run" "$hex" --seconds "$seconds" --tick 1e6 "$@" 2>&1)
}

# game_peek BUILD: the runner option that dumps the game (the start of store.S's .persistent block, 134 words)
game_peek() {
    echo "--peek $("$nm" "$out/$1.elf" | awk '$3 == "game_magic" { print $1 }'):134"
}

# stock NAME BUILD SEED PRESSES: checks the stock and waste in FRAM, from the --peek of the last run, against
# tests/stock.py's reference for that seed after PRESSES presses of STOCK
stock() {
    name=$1
    addr=$("$nm" "$out/$2.elf" | awk '$3 == "game_magic" { print toupper(substr($1, length($1) - 3)) }')
    if result=$(echo "$report" | python3 "$here/stock.py" "$addr" "$3" "$4"); then
        pass "$name piles"
    else
        fail "$name piles: $(echo "$result" | head -3 | tr '\n' ' ')"
    fi
}

# fram_peek BUILD: the runner option that dumps everything kept in FRAM (store.S's .persistent, 660 words)
fram_peek() {
    echo "--peek $("$nm" "$out/$1.elf" | awk '$3 == "game_magic" { print $1 }'):660"
}

# model NAME BUILD SEED DRAW ROLES: checks FRAM, from the --peek of the last run, against tests/klondike.py's model
# of the firmware after the presses ROLES (a file, or the names), from a chip with seed SEED and draw option DRAW
model() {
    name=$1
    addr=$("$nm" "$out/$2.elf" | awk '$3 == "game_magic" { print toupper(substr($1, length($1) - 3)) }')
    if result=$(echo "$report" | python3 "$here/klondike.py" check "$addr" "$3" "$4" "$5"); then
        pass "$name FRAM"
    else
        fail "$name FRAM: $(echo "$result" | head -4 | tr '\n' ' ')"
    fi
}

# play NAME BUILD SEED DRAW ROLES: presses ROLES (150 ms apart, from 0.5 s) without the display model, then model
play() {
    n=$(python3 -c "import sys; sys.path.insert(0, '$here'); import klondike; print(len(klondike.read_roles('$5')))")
    run_only "$2" "$(echo "0.5 + $n * 0.15 + 1" | bc)" $(fram_peek "$2") $(python3 "$here/klondike.py" pins "$5" 0.5 0.15)
    model "$@"
}

# screen_play NAME BUILD SEED DRAW ROLES: the same with the display model, checking the screen too (NAME.pbm, or
# APPROVED=OTHER)
screen_play() {
    n=$(python3 -c "import sys; sys.path.insert(0, '$here'); import klondike; print(len(klondike.read_roles('$5')))")
    screen "$1" "$2" "$(echo "0.5 + $n * 0.15 + 1" | bc)" $(fram_peek "$2") \
        $(python3 "$here/klondike.py" pins "$5" 0.5 0.15)
    model "$@"
}

# cycles: the MCLK cycles the last run counted (the CPU's time awake)
cycles() {
    echo "$report" | sed -n 's/^ran .*: \([0-9]*\) MCLK cycles.*/\1/p'
}

# presses PIN COUNT START: runner options pressing package pin PIN COUNT times from START seconds, 60 ms each,
# 150 ms apart
presses() {
    awk -v pin="$1" -v n="$2" -v t="$3" 'BEGIN {
        for (i = 0; i < n; i++) printf "--pin %d=0@%.2f --pin %d=z@%.2f ", pin, t + i * 0.15, pin, t + i * 0.15 + 0.06 }'
}

build game -DTEST_SEED=0x1234
build game5678 -DTEST_SEED=0x5678
build win -DTEST_SEED=0x1007 -DTEST_DRAW=1
build squeeze -DTEST_SEED=0x1234 -DTEST_SCREEN=4
build corrupt1 -DTEST_SEED=0x1234 -DTEST_CORRUPT=1
build corrupt2 -DTEST_SEED=0x1234 -DTEST_CORRUPT=2
build pattern -DTEST_SCREEN=1
build cards -DTEST_SCREEN=2
build buttons -DTEST_SCREEN=3

# Step 2: the test pattern after start-up
screen step2_pattern pattern 2
# Step 3: every card and graphic
screen step3_cards cards 2

# Step 4: the buttons. Package pins of roles 1-16: stacks 1-7 7 6 5 4 31 30 29, waste 27, stock 26 (the bottom
# row's stack 8 and 9 switches), suits 1-4 25 24 15 14, SW1-SW3 3 2 1. N=0@t holds pin N low from t seconds; N=z@t lets it go, back to its pull-up.
#   - each button once, 60 ms each, 150 ms apart;
#   - stack 1: a press that bounces (0.5 ms apart) and is held;
#   - stack 2: a release that bounces;
#   - stack 3: held for 2 s (no repeat);
#   - suit 1 and SW2 pressed 1 ms apart;
#   - stock: pressed again 200 ms after letting go.
# Each press must be exactly one event: stacks 1-3 2 each, stock 3, suit 1 2, SW2 2, every other button 1.
screen step4_buttons buttons 7.2 --peek "$("$nm" "$out/buttons.elf" | awk '$3 == "presses" { print $1 }'):9" \
    --pin 7=0@0.50 --pin 7=z@0.56 \
    --pin 6=0@0.65 --pin 6=z@0.71 \
    --pin 5=0@0.80 --pin 5=z@0.86 \
    --pin 4=0@0.95 --pin 4=z@1.01 \
    --pin 31=0@1.10 --pin 31=z@1.16 \
    --pin 30=0@1.25 --pin 30=z@1.31 \
    --pin 29=0@1.40 --pin 29=z@1.46 \
    --pin 27=0@1.55 --pin 27=z@1.61 \
    --pin 26=0@1.70 --pin 26=z@1.76 \
    --pin 25=0@1.85 --pin 25=z@1.91 \
    --pin 24=0@2.00 --pin 24=z@2.06 \
    --pin 15=0@2.15 --pin 15=z@2.21 \
    --pin 14=0@2.30 --pin 14=z@2.36 \
    --pin 3=0@2.45 --pin 3=z@2.51 \
    --pin 2=0@2.60 --pin 2=z@2.66 \
    --pin 1=0@2.75 --pin 1=z@2.81 \
    --pin 7=0@3.0 --pin 7=z@3.0005 --pin 7=0@3.001 --pin 7=z@3.0015 --pin 7=0@3.002 --pin 7=z@3.2 \
    --pin 6=0@3.4 --pin 6=z@3.6 --pin 6=0@3.6005 --pin 6=z@3.601 --pin 6=0@3.6015 --pin 6=z@3.602 \
    --pin 5=0@3.8 --pin 5=z@5.8 \
    --pin 25=0@6.0 --pin 2=0@6.001 --pin 25=z@6.2 --pin 2=z@6.2 \
    --pin 26=0@6.4 --pin 26=z@6.5 --pin 26=0@6.7 --pin 26=z@6.8
counts step4_buttons buttons "0 2 2 2 1 1 1 1 1 3 2 1 1 1 1 2 1"

# Step 5: the game. SW1 (NEW) is package pin 3; RST is pin 9 (driven high again, as its pull-up is on the board).
# The builds deal from a fixed seed (-DTEST_SEED), so each deal is known; deal.py works it out independently.
screen step5_title game 2                               # a fresh chip: no game yet, the title screen
screen step5_deal game 1.5 $(game_peek game) --pin 3=0@0.5 --pin 3=z@0.6
deal step5_deal game 0x1234 1
APPROVED=step5_deal screen step5_kept game 2 $(game_peek game) --pin 3=0@0.5 --pin 3=z@0.6 \
    --pin 9=0@1.2 --pin 9=1@1.21                        # reset after the deal: the same game, drawn again
deal step5_kept game 0x1234 1
run_only game5678 1.5 $(game_peek game5678) --pin 3=0@0.5 --pin 3=z@0.6
deal step5_seed_5678 game5678 0x5678 1

# Step 6: moves. STOCK is package pin 26. Draw 3 from 24 cards: 8 presses empty the stock, the 9th turns the waste
# back over, the 10th deals the same 3 cards as the first.
run_only game 3 $(game_peek game) --pin 3=0@0.5 --pin 3=z@0.6 $(presses 26 9 1.0)
stock step6_stock_turnover game 0x1234 9
run_only game 3 $(game_peek game) --pin 3=0@0.5 --pin 3=z@0.6 $(presses 26 10 1.0)
stock step6_stock_second_pass game 0x1234 10
# Scripted play (tests/sequences.py), and a whole winning game from seed 0x1007 in draw 1 (tests/solve.py),
# checked against the model (tests/klondike.py) byte for byte: the piles, counts, undo log, score, statistics
play step6_moves game 0x1234 3 "$here/moves.txt"
screen_play step6_win win 0x1007 1 "$here/win.txt"     # 216 presses: the longest test; the win screen at the end

# Step 7: the interface. Seed 0x1234: column 1 is 9C, column 2 ends 2C, column 7 ends 5C.
screen_play step7_select game 0x1234 3 "NEW T7"         # column 7's top card selected: inverted
screen_play step7_cant game 0x1234 3 "NEW T1 T2"        # 9C on 2C: not allowed; said, and still selected
screen_play step7_waste game 0x1234 3 "NEW STOCK STOCK WASTE"   # draw 3: the top three fanned, the top selected
screen_play step7_confirm game 0x1234 3 "NEW STOCK NEW"         # NEW mid-game asks first
screen step7_squeeze squeeze 2 --pin 4=0@1.0 --pin 4=z@1.06     # every column height; the tallest selected

# Step 8: undo (play, then undo it all, and two more), scoring, a pass limit, and the options screen
play step8_undo game 0x1234 3 "$here/undo.txt"
play step8_standard game 0x1234 3 "$here/standard.txt"
play step8_vegas game 0x1234 3 "$here/vegas.txt"
play step8_passes game 0x1234 3 "$here/passes.txt"
screen_play step8_options game 0x1234 3 "NEW OPTIONS F1 F2 F3 F4"     # every setting changed; S4 asks first

# Step 9: saving. A reset mid-game comes back exactly (the same picture as before it); a game damaged after its
# checksum was written is kept if its cards are all there (but not its undo log), else dropped for the title.
screen_play step9_before game 0x1234 3 "NEW T5 T1 STOCK STOCK"
APPROVED=step9_before screen_play step9_resume game 0x1234 3 "NEW T5 T1 STOCK STOCK RESET"
play step9_damaged_count corrupt1 0x1234 3 "NEW T5 T1 STOCK STOCK RESET_CORRUPT_MOVES UNDO"
APPROVED=step5_title screen_play step9_damaged_cards corrupt2 0x1234 3 "NEW T5 T1 STOCK RESET_CORRUPT_CARDS"

# Step 10: power. Idle: after a deal, 5 minutes asleep may cost only the two TB0 wake-ups for the watchdog (a few
# hundred cycles each). A press: at most 150000 cycles (19 ms awake), averaged over 40 presses of real play.
run_only game 2.5 --pin 3=0@0.5 --pin 3=z@0.6
short=$(cycles)
run_only game 300 --pin 3=0@0.5 --pin 3=z@0.6
long=$(cycles)
sr=$(echo "$report" | sed -n 's/.* SR=\([0-9A-Fa-f]*\) .*/\1/p')
if [ $((long - short)) -gt 5000 ] || [ $((0x$sr & 0xD0)) -ne $((0xD0)) ]; then
    fail "step10_idle: $((long - short)) cycles awake in 5 minutes idle (at most 5000), SR=$sr"
else
    pass "step10_idle: $((long - short)) cycles awake in 5 minutes idle"
fi
first=$(python3 -c "import sys; sys.path.insert(0, '$here'); import klondike; print(' '.join(klondike.read_roles('$here/moves.txt')[:41]))")
report=$("$run" "$out/game.hex" --seconds 9 --tick 8e6 $(python3 "$here/klondike.py" pins "NEW" 0.5 0.15) 2>&1)
one=$(cycles)
report=$("$run" "$out/game.hex" --seconds 9 --tick 8e6 $(python3 "$here/klondike.py" pins "$first" 0.5 0.15) 2>&1)
per=$(( ($(cycles) - one) / 40 ))
if [ "$per" -gt 150000 ]; then
    fail "step10_press: $per cycles a press (at most 150000)"
else
    pass "step10_press: $per cycles a press ($((per / 8000)) ms at 8 MHz)"
fi

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
