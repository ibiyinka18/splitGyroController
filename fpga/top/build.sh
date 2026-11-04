#!/usr/bin/env bash
#
# Build and flash subsystem 1 (SPI -> ICM-45686) for the Lattice iCEstick.
#
#   ./fpga/top/build.sh          synthesise, place/route, pack
#   ./fpga/top/build.sh prog     ...and flash the attached iCEstick
#
# Run from the repository root.
#
set -euo pipefail

OSS="$HOME/oss-cad-suite/bin"
BUILD="build"
TOP="top"

SOURCES=(
    fpga/top/top.v
    fpga/imu_controller/imu_controller.v
    fpga/spi_master/spi_master.v
    fpga/uart_tx_rx/sensor_packet.v
    fpga/uart_tx_rx/uart_tx.v
    fpga/cartridge_id/cartridge_id.v
)
PCF="fpga/top/icestick.pcf"

mkdir -p "$BUILD"

echo "==> synthesis (yosys)"
"$OSS/yosys" -q -p "synth_ice40 -top $TOP -json $BUILD/$TOP.json" "${SOURCES[@]}"

echo "==> place and route (nextpnr-ice40)"
"$OSS/nextpnr-ice40" --hx1k --package tq144 \
    --json "$BUILD/$TOP.json" \
    --pcf  "$PCF" \
    --asc  "$BUILD/$TOP.asc" 2>&1 | grep -E "Device utilisation|ICESTORM_LC|SB_IO|Max frequency|ERROR"

echo "==> pack bitstream (icepack)"
"$OSS/icepack" "$BUILD/$TOP.asc" "$BUILD/$TOP.bin"

echo "==> built $BUILD/$TOP.bin"

if [[ "${1:-}" == "prog" ]]; then
    echo "==> flashing (iceprog)"
    "$OSS/iceprog" "$BUILD/$TOP.bin"
    echo "==> done"
else
    echo "    to flash:  ./fpga/top/build.sh prog"
fi
