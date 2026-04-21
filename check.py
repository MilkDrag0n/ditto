#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


QUEUE_RE = re.compile(
	r"queue commit meta=(?P<meta>[01]+) carry_comps=(?P<carry>[01]+) "
	r"data=(?P<data>[0-9a-fA-F]+) weight=(?P<weight>[0-9a-fA-F]+)"
)
PE_RE = re.compile(r"pe result=(?P<value>[0-9a-fA-F]+)")
FINAL_RE = re.compile(r"debug result=(?P<debug>[0-9a-fA-F]+) full=(?P<full>[0-9a-fA-F]+)")


@dataclass
class QueuePacket:
	meta: int
	carry: int
	data: int
	weight: int


def read_hex_values(path: Path) -> list[int]:
	return [int(token, 16) for token in path.read_text().split()]


def parse_finish_count(path: Path) -> int:
	text = path.read_text()
	match = re.search(r"data_pst_addr\s*==\s*8'b([01_]+)", text)
	if not match:
		raise ValueError(f"failed to find finish count in {path}")
	return int(match.group(1).replace("_", ""), 2)


def sign_extend_4(value: int) -> int:
	return value - 16 if value & 0x8 else value


def sign_extend_8(value: int) -> int:
	return value - 256 if value & 0x80 else value


def mask_u18(value: int) -> int:
	return value & ((1 << 18) - 1)


def mask_u32(value: int) -> int:
	return value & 0xFFFF_FFFF


def classify_diff(diff: int) -> tuple[bool, bool]:
	sign_ext = 0xF if (diff & 0x8) else 0x0
	is_wide = ((diff >> 4) & 0xF) != sign_ext
	is_non_zero = (diff & 0xF) != 0
	return is_wide, is_non_zero


def set_nibble(value: int, index: int, nibble: int) -> int:
	return (value & ~(0xF << (4 * index))) | ((nibble & 0xF) << (4 * index))


def set_byte(value: int, index: int, byte: int) -> int:
	return (value & ~(0xFF << (8 * index))) | ((byte & 0xFF) << (8 * index))


def build_queue_packets(
	data_pst_values: list[int],
	data_now_values: list[int],
	weight_values: list[int],
	finish_count: int,
) -> list[QueuePacket]:
	diffs = [
		((data_now_values[index] - data_pst_values[index]) & 0xFF)
		for index in range(finish_count)
	]
	packets: list[QueuePacket] = []

	status = 0
	meta = 0
	carry = 0
	data_queue = 0
	weight_queue = 0
	buffer_valid = False
	data_buffer = 0
	weight_buffer = 0
	carry_buffer = 0

	for diff, weight in zip(diffs, weight_values[:finish_count]):
		is_wide, _ = classify_diff(diff)
		if diff == 0:
			continue

		if status == 0xF:
			packets.append(QueuePacket(meta, carry, data_queue, weight_queue))
			if buffer_valid:
				if is_wide:
					status = 0b0111
					meta = 0b01
					carry = (carry & 0b01) | 0b10
					data_queue = ((diff & 0xF) << 8) | (((diff >> 4) & 0xF) << 4) | data_buffer
					weight_queue = ((weight & 0xFF) << 16) | ((weight & 0xFF) << 8) | weight_buffer
				else:
					status = 0b0011
					meta = 0
					carry = 0
					data_queue = ((diff & 0xF) << 4) | data_buffer
					weight_queue = ((weight & 0xFF) << 8) | weight_buffer
				buffer_valid = False
				data_buffer = 0
				weight_buffer = 0
				carry_buffer = 0
				continue

			if is_wide:
				status = 0b0011
				meta = 0b01
				carry = (carry & 0b10) | 0b01
				data_queue = diff
				weight_queue = (weight << 8) | weight
			else:
				status = 0b0001
				meta = 0
				carry = 0
				data_queue = diff & 0xF
				weight_queue = weight
			continue

		if not is_wide:
			if status == 0b0000:
				status = 0b0001
				meta = 0
				carry = 0
				data_queue = diff & 0xF
				weight_queue = weight
			elif status == 0b0001:
				status = 0b0011
				data_queue = set_nibble(data_queue, 1, diff & 0xF)
				weight_queue = set_byte(weight_queue, 1, weight)
			elif status == 0b0011:
				status = 0b0111
				data_queue = set_nibble(data_queue, 2, diff & 0xF)
				weight_queue = set_byte(weight_queue, 2, weight)
			elif status == 0b0111:
				status = 0b1111
				data_queue = set_nibble(data_queue, 3, diff & 0xF)
				weight_queue = set_byte(weight_queue, 3, weight)
			continue

		if status == 0b0000:
			status = 0b0011
			meta |= 0b01
			carry = (carry & 0b10) | 0b01
			data_queue = (data_queue & ~0xFF) | diff
			weight_queue = (weight_queue & ~0xFFFF) | (weight << 8) | weight
		elif status == 0b0001:
			status = 0b0111
			meta |= 0b01
			carry = (carry & 0b01) | 0b10
			data_queue = set_nibble(data_queue, 1, (diff >> 4) & 0xF)
			data_queue = set_nibble(data_queue, 2, diff & 0xF)
			weight_queue = (weight_queue & ~0x00FFFF00) | (weight << 8) | (weight << 16)
		elif status == 0b0011:
			status = 0b1111
			meta |= 0b10
			carry = (carry & 0b01) | 0b10
			data_queue = (data_queue & ~0xFF00) | (diff << 8)
			weight_queue = (weight_queue & ~0xFFFF0000) | (weight << 16) | (weight << 24)
		elif status == 0b0111:
			status = 0b1111
			meta |= 0b10
			data_queue = set_nibble(data_queue, 3, (diff >> 4) & 0xF)
			weight_queue = set_byte(weight_queue, 3, weight)
			buffer_valid = True
			data_buffer = diff & 0xF
			weight_buffer = weight
			carry_buffer = 0

	if status:
		packets.append(QueuePacket(meta, carry, data_queue, weight_queue))
	if buffer_valid:
		packets.append(QueuePacket(0, carry_buffer, data_buffer, weight_buffer))

	return packets


def calc_pe_result(packet: QueuePacket) -> int:
	n0 = (packet.data >> 0) & 0xF
	n1 = (packet.data >> 4) & 0xF
	n2 = (packet.data >> 8) & 0xF
	n3 = (packet.data >> 12) & 0xF

	w0 = sign_extend_8((packet.weight >> 0) & 0xFF)
	w1 = sign_extend_8((packet.weight >> 8) & 0xFF)
	w2 = sign_extend_8((packet.weight >> 16) & 0xFF)
	w3 = sign_extend_8((packet.weight >> 24) & 0xFF)

	comp = 0
	if (packet.carry & 0b01) and (n0 & 0x8):
		comp += w0
	if (packet.carry & 0b10) and (n2 & 0x8):
		comp += w2

	return (
		((sign_extend_4(n1) * w1) << 4 if packet.meta & 0b01 else sign_extend_4(n1) * w1)
		+ sign_extend_4(n0) * w0
		+ ((sign_extend_4(n3) * w3) << 4 if packet.meta & 0b10 else sign_extend_4(n3) * w3)
		+ sign_extend_4(n2) * w2
		+ (comp << 4)
	)


def calc_final_result(pe_results: list[int]) -> int:
	total = 0
	for value in pe_results:
		total = mask_u32(total + value)
	return total


def parse_log(log_path: Path) -> tuple[list[QueuePacket], list[int], int | None]:
	queue_packets: list[QueuePacket] = []
	pe_results: list[int] = []
	final_result: int | None = None

	for line in log_path.read_text().splitlines():
		queue_match = QUEUE_RE.search(line)
		if queue_match:
			queue_packets.append(
				QueuePacket(
					meta=int(queue_match.group("meta"), 2),
					carry=int(queue_match.group("carry"), 2),
					data=int(queue_match.group("data"), 16),
					weight=int(queue_match.group("weight"), 16),
				)
			)
			continue

		pe_match = PE_RE.search(line)
		if pe_match:
			pe_results.append(int(pe_match.group("value"), 16))
			continue

		final_match = FINAL_RE.search(line)
		if final_match:
			final_result = int(final_match.group("full"), 16)

	return queue_packets, pe_results, final_result


def format_queue(packet: QueuePacket) -> str:
	return (
		f"queue commit meta={packet.meta:02b} carry_comps={packet.carry:02b} "
		f"data={packet.data:04x} weight={packet.weight:08x}"
	)


def format_pe(value: int) -> str:
	return f"pe result={mask_u18(value):05x}"


def format_final(value: int) -> str:
	return f"debug result={mask_u32(value):08x}"


def compare_section(name: str, expected: list[str], actual: list[str]) -> bool:
	print(name)
	ok = len(expected) == len(actual)
	for index in range(max(len(expected), len(actual))):
		expected_line = expected[index] if index < len(expected) else "<missing>"
		actual_line = actual[index] if index < len(actual) else "<missing>"
		match = expected_line == actual_line
		ok &= match
		print(
			f"  [{index}] {'PASS' if match else 'FAIL'} "
			f"expected: {expected_line} | actual: {actual_line}"
		)
	print()
	return ok


def main() -> int:
	parser = argparse.ArgumentParser(description="Check queue packets, PE results and final result")
	parser.add_argument("--log", default="build/sim.log")
	parser.add_argument("--data-pst", default="RTL/testbench/data/data_pst_mem.hex")
	parser.add_argument("--data-now", default="RTL/testbench/data/data_now_mem.hex")
	parser.add_argument("--weight", default="RTL/testbench/data/weight_mem.hex")
	parser.add_argument("--control", default="RTL/control_unit.v")
	args = parser.parse_args()

	log_path = Path(args.log)
	if not log_path.exists():
		print(f"log file not found: {log_path}", file=sys.stderr)
		return 2

	data_pst_values = read_hex_values(Path(args.data_pst))
	data_now_values = read_hex_values(Path(args.data_now))
	weight_values = read_hex_values(Path(args.weight))
	finish_count = parse_finish_count(Path(args.control))

	expected_queue = build_queue_packets(
		data_pst_values,
		data_now_values,
		weight_values,
		finish_count,
	)
	expected_pe = [calc_pe_result(packet) for packet in expected_queue]
	expected_final = calc_final_result(expected_pe)

	actual_queue, actual_pe, actual_final = parse_log(log_path)

	expected_queue_lines = [format_queue(packet) for packet in expected_queue]
	actual_queue_lines = [format_queue(packet) for packet in actual_queue]
	expected_pe_lines = [format_pe(value) for value in expected_pe]
	actual_pe_lines = [format_pe(value) for value in actual_pe]

	all_ok = True
	print(f"finish_count: {finish_count}")
	print()
	all_ok &= compare_section("Queue Results", expected_queue_lines, actual_queue_lines)
	all_ok &= compare_section("PE Results", expected_pe_lines, actual_pe_lines)

	expected_final_line = format_final(expected_final)
	actual_final_line = format_final(actual_final) if actual_final is not None else "<missing>"
	final_ok = expected_final_line == actual_final_line
	all_ok &= final_ok
	print(
		f"Final Result: {'PASS' if final_ok else 'FAIL'} "
		f"expected: {expected_final_line} | actual: {actual_final_line}"
	)
	print()
	print(f"Overall: {'PASS' if all_ok else 'FAIL'}")
	return 0 if all_ok else 1


if __name__ == "__main__":
	raise SystemExit(main())
