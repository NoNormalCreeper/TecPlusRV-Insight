#!/usr/bin/env python3
"""把裸机 firmware.bin 转成 Verilog $readmemh 可读的 32-bit word 文本。

输入 bin 是小端字节流；输出每行一个 32-bit hex word，对应 BRAM 的一个 word。
可选第三个参数用于填零到固定 word 数，避免大 BRAM 初始化时 $readmemh 报短文件 warning。
"""

import struct
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print("用法：bin2mem.py <输入.bin> <输出.mem> [最少 word 数]", file=sys.stderr)
        return 1

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    min_words = int(sys.argv[3], 0) if len(sys.argv) == 4 else 0

    data = input_path.read_bytes()
    if len(data) % 4 != 0:
        # BRAM 按 32-bit word 初始化，不足 4 字节时末尾补 0。
        data += b"\x00" * (4 - (len(data) % 4))

    lines = []
    for offset in range(0, len(data), 4):
        # RISC-V little-endian：文件里的低地址字节是 word 的低 8 bit。
        word = struct.unpack("<I", data[offset:offset + 4])[0]
        lines.append(f"{word:08x}\n")

    if len(lines) < min_words:
        lines.extend("00000000\n" for _ in range(min_words - len(lines)))

    output_path.write_text("".join(lines), encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
