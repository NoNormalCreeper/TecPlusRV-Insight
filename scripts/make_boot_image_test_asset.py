#!/usr/bin/env python3
"""生成供 bootloader 上板全量读回的确定性 SDRAM asset。"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path


MAGIC = 0x31565442  # little-endian "BTV1"
VERSION = 1
HEADER_WORDS = 4
MAX_DATA_BYTES = 1024 * 1024
PATTERN_MULTIPLIER = 0x9E3779B9


def pattern_word(index: int, seed: int) -> int:
    return (seed ^ ((index * PATTERN_MULTIPLIER) & 0xFFFFFFFF)) & 0xFFFFFFFF


def build_asset(data_bytes: int, seed: int) -> bytes:
    if data_bytes <= 0 or data_bytes > MAX_DATA_BYTES or data_bytes % 4:
        raise ValueError(
            f"data bytes 必须是 4..{MAX_DATA_BYTES} 范围内的 4-byte 整数倍"
        )
    if not 0 <= seed <= 0xFFFFFFFF:
        raise ValueError("seed 必须位于 0..0xffffffff")

    data_words = data_bytes // 4
    words = [MAGIC, VERSION, data_words, seed]
    words.extend(pattern_word(index, seed) for index in range(data_words))
    return struct.pack(f"<{len(words)}I", *words)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="生成 bootloader SDRAM 全量读回 asset")
    parser.add_argument("--data-bytes", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x12345678)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mem-output", type=Path, help="可选的 32-bit hex 仿真输入")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    data = build_asset(args.data_bytes, args.seed)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)

    if args.mem_output is not None:
        args.mem_output.parent.mkdir(parents=True, exist_ok=True)
        words = struct.unpack(f"<{len(data) // 4}I", data)
        args.mem_output.write_text(
            "".join(f"{word:08x}\n" for word in words), encoding="ascii"
        )

    print(
        f"boot image test asset：{args.output} "
        f"(data={args.data_bytes} bytes, total={len(data)} bytes, seed=0x{args.seed:08x})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
