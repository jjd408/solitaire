#!/usr/bin/env bash
# Downloads and assembles the MSP430-GCC toolchain locally under fw/toolchain/.
# Not committed to git (it's ~430MB) - run this once after cloning.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TC="$HERE/toolchain"
GCC_URL="http://software-dl.ti.com/msp430/msp430_public_sw/mcu/msp430/MSPGCC/9_3_1_2/export/msp430-gcc-9.3.1.11_linux64.tar.bz2"
SUPPORT_URL="https://dr-download.ti.com/software-development/ide-configuration-compiler-or-debugger/MD-LlCjWuAbzH/8.3.1.0/msp430-gcc-support-files-1.208.zip"

if [ -x "$TC/bin/msp430-elf-gcc" ]; then
    echo "Toolchain already present at $TC"
else
    mkdir -p "$TC"
    echo "Downloading msp430-elf-gcc/gdb (~62MB)..."
    curl -sL -o /tmp/msp430-gcc.tar.bz2 "$GCC_URL"
    tar xjf /tmp/msp430-gcc.tar.bz2 --strip-components=1 -C "$TC"
    rm /tmp/msp430-gcc.tar.bz2
fi

if [ -f "$TC/msp430-elf/include/devices/msp430fr2355.h" ]; then
    echo "Device support files already present"
else
    echo "Downloading device headers/linker scripts (~21MB)..."
    curl -sL -o /tmp/msp430-support.zip "$SUPPORT_URL"
    mkdir -p /tmp/msp430-support-extract "$TC/msp430-elf/include/devices"
    unzip -q /tmp/msp430-support.zip -d /tmp/msp430-support-extract
    cp /tmp/msp430-support-extract/msp430-gcc-support-files/include/* "$TC/msp430-elf/include/devices/"
    rm -rf /tmp/msp430-support.zip /tmp/msp430-support-extract
fi

# The prebuilt msp430-elf-gdb links against libncursesw.so.5 / libtinfo.so.5,
# which modern distros (e.g. Debian 13/trixie) no longer ship. Rather than
# touch the system, point gdb at local symlinks onto the .so.6 the distro has.
mkdir -p "$TC/compat-lib"
for lib in libncursesw libtinfo; do
    so6=$(ldconfig -p 2>/dev/null | grep "${lib}\.so\.6 " | awk '{print $NF}' | head -1)
    if [ -n "$so6" ] && [ ! -e "$TC/compat-lib/${lib}.so.5" ]; then
        ln -sf "$so6" "$TC/compat-lib/${lib}.so.5"
    fi
done

echo "Done. Add $TC/bin to PATH, and set LD_LIBRARY_PATH=$TC/compat-lib when running msp430-elf-gdb."
