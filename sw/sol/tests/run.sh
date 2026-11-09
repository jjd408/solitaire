#!/bin/sh
# Automated tests for the solitaire firmware, on the simulator (see sw/PLAN.md, Testing).
#
# Builds the firmware from sw/sol/src, runs it on msp430_run with the display model connected, and checks each
# scenario: the display's report (no timing problems, EXTCOMIN 57-66 Hz, display on) and the screen against an
# approved picture, NAME.pbm in this folder.
#
#   tests/run.sh            run every test
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
    inc=$(dirname "$bin")/include
else
    gcc=msp430-elf-gcc
    objcopy=msp430-elf-objcopy
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

build pattern -DTEST_SCREEN=1
build cards -DTEST_SCREEN=2

# Step 2: the test pattern after start-up
screen step2_pattern pattern 2
# Step 3: every card and graphic
screen step3_cards cards 2

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
