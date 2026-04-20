#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_DIR="$SCRIPT_DIR/build"
SIM_OUT="$BUILD_DIR/ditto_sim.out"
LOG_FILE="$BUILD_DIR/sim.log"
VCD_FILE="$BUILD_DIR/ditto_tb.vcd"

mkdir -p "$BUILD_DIR"

iverilog -g2012 -DDEBUG -Wall -o "$SIM_OUT" \
	"$SCRIPT_DIR/RTL/ditto_top.v" \
	"$SCRIPT_DIR/RTL/control_unit.v" \
	"$SCRIPT_DIR/RTL/encoding_unit.v" \
	"$SCRIPT_DIR/RTL/compute_unit.v" \
	"$SCRIPT_DIR/RTL/mini_cache.v" \
	"$SCRIPT_DIR/RTL/testbench/ditto_tb.v"

(
	cd "$SCRIPT_DIR"
	vvp "$SIM_OUT"
) | tee "$LOG_FILE"

printf 'simulator: %s\n' "$SIM_OUT"
printf 'log      : %s\n' "$LOG_FILE"
printf 'waveform : %s\n' "$VCD_FILE"
