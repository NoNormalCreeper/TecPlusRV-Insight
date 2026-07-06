#!/usr/bin/env python3
"""把裸机 firmware.bin 转成 Verilog $readmemh 可读的 32-bit word 文本。

输入 bin 是小端字节流；输出每行一个 32-bit hex word，对应 BRAM 的一个 word。
"""

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
        # BRAM 按 32-bit word 初始化，不足 4 字节时末尾补 0。
        data += b"\x00" * (4 - (len(data) % 4))

    lines = []
    for offset in range(0, len(data), 4):
        # RISC-V little-endian：文件里的低地址字节是 word 的低 8 bit。
        word = struct.unpack("<I", data[offset:offset + 4])[0]
        lines.append(f"{word:08x}\n")

    output_path.write_text("".join(lines), encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
