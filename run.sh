#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_DIR="$SCRIPT_DIR/build"
SIM_OUT="$BUILD_DIR/ditto_sim.out"
LOG_FILE="$BUILD_DIR/sim.log"
CHECK_LOG="$BUILD_DIR/check.log"
TEST_LOG="$BUILD_DIR/test.log"
VCD_FILE="$BUILD_DIR/ditto_tb.vcd"

mkdir -p "$BUILD_DIR"

run_sim() {
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
	) | tee "$LOG_FILE" >/dev/null

	printf 'simulator: %s\n' "$SIM_OUT"
	printf 'log      : %s\n' "$LOG_FILE"
	printf 'waveform : %s\n' "$VCD_FILE"
}

run_check() {
	run_sim
	(
		cd "$SCRIPT_DIR"
		python3 "$SCRIPT_DIR/check.py" --log "$LOG_FILE"
	) | tee "$CHECK_LOG"

	printf 'check log: %s\n' "$CHECK_LOG"
}

run_test() {
	run_sim
	(
		cd "$SCRIPT_DIR"
		python3 "$SCRIPT_DIR/check.py" --log "$LOG_FILE" --direct-final-only
	) | tee "$TEST_LOG"

	printf 'test log : %s\n' "$TEST_LOG"
}

case "${1:-}" in
	"")
		run_sim
		;;
	--check)
		run_check
		;;
	--test)
		run_test
		;;
	*)
		printf 'usage: %s [--check|--test]\n' "$0" >&2
		exit 2
		;;
esac
