#!/usr/bin/env python3

import struct
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("用法：bin2mem.py <输入.bin> <输出.mem>", file=sys.stderr)
        return 1

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    data = input_path.read_bytes()
    if len(data) % 4 != 0:
        data += b"\x00" * (4 - (len(data) % 4))

    lines = []
    for offset in range(0, len(data), 4):
        word = struct.unpack("<I", data[offset:offset + 4])[0]
        lines.append(f"{word:08x}\n")

    output_path.write_text("".join(lines), encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
