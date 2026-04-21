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


def parse_batch_size(path: Path) -> int:
	text = path.read_text()
	match = re.search(r"(?:data_pst_addr|data_now_addr|weight_addr)\s*==\s*8'b([01_]+)", text)
	if match:
		return int(match.group(1).replace("_", ""), 2)

	if re.search(r"(?:data_pst_addr|data_now_addr|weight_addr)\[3:0\]\s*==\s*4'hf", text, re.IGNORECASE):
		return 16

	if re.search(r"(?:data_pst_addr|data_now_addr|weight_addr)\[3:0\]\s*==\s*4'b1111", text):
		return 16

	raise ValueError(f"failed to find batch size in {path}")


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


def calc_input_final_result(
	data_pst_values: list[int],
	data_now_values: list[int],
	weight_values: list[int],
	finish_count: int,
) -> int:
	total = 0
	for data_pst, data_now, weight in zip(
		data_pst_values[:finish_count],
		data_now_values[:finish_count],
		weight_values[:finish_count],
	):
		diff = sign_extend_8((data_now - data_pst) & 0xFF)
		total = mask_u32(total + diff * sign_extend_8(weight & 0xFF))
	return total


def parse_log(log_path: Path) -> tuple[list[QueuePacket], list[int], list[int]]:
	queue_packets: list[QueuePacket] = []
	pe_results: list[int] = []
	final_results: list[int] = []

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
			final_results.append(int(final_match.group("full"), 16))

	return queue_packets, pe_results, final_results


def format_queue(packet: QueuePacket) -> str:
	return (
		f"queue commit meta={packet.meta:02b} carry_comps={packet.carry:02b} "
		f"data={packet.data:04x} weight={packet.weight:08x}"
	)


def format_pe(value: int) -> str:
	return f"pe result={mask_u18(value):05x}"


def format_final(value: int) -> str:
	return f"debug result={mask_u32(value):08x}"


def format_batch_item_label(batch_index: int, item_index: int) -> str:
	return f"batch {batch_index} [{item_index}]"


def format_batch_label(batch_index: int) -> str:
	return f"batch {batch_index}"


def compare_section(
	name: str,
	expected: list[str],
	actual: list[str],
	expected_labels: list[str],
	actual_labels: list[str],
) -> bool:
	print(name)
	ok = len(expected) == len(actual)
	for index in range(max(len(expected), len(actual))):
		expected_line = expected[index] if index < len(expected) else "<missing>"
		actual_line = actual[index] if index < len(actual) else "<missing>"
		expected_label = expected_labels[index] if index < len(expected_labels) else "<missing>"
		actual_label = actual_labels[index] if index < len(actual_labels) else "<missing>"
		match = expected_line == actual_line
		ok &= match
		if expected_label == actual_label or actual_label == "<missing>":
			label = expected_label
		elif expected_label == "<missing>":
			label = actual_label
		else:
			label = f"expected {expected_label}, actual {actual_label}"
		print(
			f"  {label} {'PASS' if match else 'FAIL'} "
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
	parser.add_argument("--direct-final-only", action="store_true")
	args = parser.parse_args()

	log_path = Path(args.log)
	if not log_path.exists():
		print(f"log file not found: {log_path}", file=sys.stderr)
		return 2

	data_pst_values = read_hex_values(Path(args.data_pst))
	data_now_values = read_hex_values(Path(args.data_now))
	weight_values = read_hex_values(Path(args.weight))
	batch_size = parse_batch_size(Path(args.control))
	total_count = min(len(data_pst_values), len(data_now_values), len(weight_values))
	batch_count = total_count // batch_size

	expected_queue: list[QueuePacket] = []
	expected_queue_labels: list[str] = []
	expected_pe: list[int] = []
	expected_pe_labels: list[str] = []
	expected_finals: list[int] = []
	expected_final_labels: list[str] = []
	expected_input_finals: list[int] = []
	expected_input_final_labels: list[str] = []
	for batch_index in range(batch_count):
		start = batch_index * batch_size
		end = start + batch_size
		batch_packets = build_queue_packets(
			data_pst_values[start:end],
			data_now_values[start:end],
			weight_values[start:end],
			batch_size,
		)
		batch_pe_packets = [packet for packet in batch_packets if packet.data != 0]
		batch_pe = [calc_pe_result(packet) for packet in batch_pe_packets]
		expected_queue.extend(batch_packets)
		expected_queue_labels.extend(
			format_batch_item_label(batch_index, item_index)
			for item_index in range(len(batch_packets))
		)
		expected_pe.extend(batch_pe)
		expected_pe_labels.extend(
			format_batch_item_label(batch_index, item_index)
			for item_index in range(len(batch_pe))
		)
		expected_finals.append(calc_final_result(batch_pe))
		expected_final_labels.append(format_batch_label(batch_index))
		expected_input_finals.append(
			calc_input_final_result(
				data_pst_values[start:end],
				data_now_values[start:end],
				weight_values[start:end],
				batch_size,
			)
		)
		expected_input_final_labels.append(format_batch_label(batch_index))

	actual_queue, actual_pe, actual_finals = parse_log(log_path)
	actual_queue_labels: list[str] = []
	actual_pe_labels: list[str] = []
	actual_final_labels: list[str] = []
	actual_batch_index = 0
	actual_queue_index = 0
	actual_pe_index = 0
	for line in log_path.read_text().splitlines():
		if QUEUE_RE.search(line):
			actual_queue_labels.append(format_batch_item_label(actual_batch_index, actual_queue_index))
			actual_queue_index += 1
			continue
		if PE_RE.search(line):
			actual_pe_labels.append(format_batch_item_label(actual_batch_index, actual_pe_index))
			actual_pe_index += 1
			continue
		if FINAL_RE.search(line):
			actual_final_labels.append(format_batch_label(actual_batch_index))
			actual_batch_index += 1
			actual_queue_index = 0
			actual_pe_index = 0

	expected_queue_lines = [format_queue(packet) for packet in expected_queue]
	actual_queue_lines = [format_queue(packet) for packet in actual_queue]
	expected_pe_lines = [format_pe(value) for value in expected_pe]
	actual_pe_lines = [format_pe(value) for value in actual_pe]
	expected_final_lines = [format_final(value) for value in expected_finals]
	actual_final_lines = [format_final(value) for value in actual_finals]
	expected_input_final_lines = [format_final(value) for value in expected_input_finals]

	all_ok = True
	print(f"batch_size: {batch_size}")
	print()
	if args.direct_final_only:
		all_ok &= compare_section(
			"Input Final Results",
			expected_input_final_lines,
			actual_final_lines,
			expected_input_final_labels,
			actual_final_labels,
		)
		print(f"Overall: {'PASS' if all_ok else 'FAIL'}")
		return 0 if all_ok else 1

	all_ok &= compare_section(
		"Queue Results",
		expected_queue_lines,
		actual_queue_lines,
		expected_queue_labels,
		actual_queue_labels,
	)
	all_ok &= compare_section(
		"PE Results",
		expected_pe_lines,
		actual_pe_lines,
		expected_pe_labels,
		actual_pe_labels,
	)

	all_ok &= compare_section(
		"Final Results",
		expected_final_lines,
		actual_final_lines,
		expected_final_labels,
		actual_final_labels,
	)
	all_ok &= compare_section(
		"Input Final Results",
		expected_input_final_lines,
		actual_final_lines,
		expected_input_final_labels,
		actual_final_labels,
	)

	print(f"Overall: {'PASS' if all_ok else 'FAIL'}")
	return 0 if all_ok else 1


if __name__ == "__main__":
	raise SystemExit(main())
