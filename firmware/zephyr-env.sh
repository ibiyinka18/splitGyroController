#!/usr/bin/env bash
# Put the Zephyr toolchain on PATH for this shell:
#
#   source firmware/zephyr-env.sh
#
# Override ZEPHYR_WORKSPACE or ZEPHYR_SDK_INSTALL_DIR beforehand if your
# install lives somewhere other than the defaults below.

ZEPHYR_WORKSPACE="${ZEPHYR_WORKSPACE:-$HOME/zephyrproject}"
export ZEPHYR_BASE="$ZEPHYR_WORKSPACE/zephyr"
export ZEPHYR_SDK_INSTALL_DIR="${ZEPHYR_SDK_INSTALL_DIR:-$HOME/zephyr-sdk-1.0.1}"
export PATH="$ZEPHYR_WORKSPACE/.venv/bin:/opt/homebrew/bin:$PATH"

if [ ! -d "$ZEPHYR_BASE" ]; then
    echo "zephyr not found at $ZEPHYR_BASE" >&2
    return 1 2>/dev/null || exit 1
fi

echo "zephyr env ready ($(west --version 2>/dev/null))"
echo "  build:  west build -p always -b esp32s3_devkitc/esp32s3/procpu <app-dir>"
echo "  flash:  west flash"
