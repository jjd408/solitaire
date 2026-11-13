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

    approved=$here/$name.pbm
    new=$here/$name.new.pbm
    if [ ! -f "$approved" ]; then
        cp "$got" "$new"
        problems="$problems; no approved picture yet: look at tests/$name.new.pbm and, if it's right, rename it"
        problems="$problems to $name.pbm"
    elif ! cmp -s "$got" "$approved"; then
        cp "$got" "$new"
        problems="$problems; the screen differs from tests/$name.pbm: see tests/$name.new.pbm"
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

build pattern -DTEST_SCREEN=1
build cards -DTEST_SCREEN=2
build buttons -DTEST_SCREEN=3

# Step 2: the test pattern after start-up
screen step2_pattern pattern 2
# Step 3: every card and graphic
screen step3_cards cards 2

# Step 4: the buttons. Package pins of roles 1-16: stacks 1-9 7 6 5 4 31 30 29 27 26, suits 1-4 25 24 15 14,
# SW1-SW3 3 2 1. N=0@t holds pin N low from t seconds; N=z@t lets it go, back to its pull-up.
#   - each button once, 60 ms each, 150 ms apart;
#   - stack 1: a press that bounces (0.5 ms apart) and is held;
#   - stack 2: a release that bounces;
#   - stack 3: held for 2 s (no repeat);
#   - suit 1 and SW2 pressed 1 ms apart;
#   - stack 9: pressed again 200 ms after letting go.
# Each press must be exactly one event: stacks 1-3 2 each, stack 9 3, suit 1 2, SW2 2, every other button 1.
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

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
