#!/usr/bin/env python3
"""boot image board-test asset 生成器的最小回归。"""

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

import make_boot_image_test_asset as asset_tool


class BootImageAssetTest(unittest.TestCase):
    def test_build_asset_has_expected_header_and_pattern(self) -> None:
        data = asset_tool.build_asset(16, 0x12345678)
        words = struct.unpack(f"<{len(data) // 4}I", data)

        self.assertEqual(
            words[:4],
            (asset_tool.MAGIC, asset_tool.VERSION, 4, 0x12345678),
        )
        self.assertEqual(
            words[4:],
            tuple(asset_tool.pattern_word(index, 0x12345678) for index in range(4)),
        )

    def test_build_asset_rejects_invalid_size(self) -> None:
        for size in (0, 3, asset_tool.MAX_DATA_BYTES + 4):
            with self.subTest(size=size):
                with self.assertRaises(ValueError):
                    asset_tool.build_asset(size, 1)

    def test_cli_writes_binary_and_exact_mem_words(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "pattern.bin"
            mem_output = Path(temp_dir) / "pattern.mem"

            result = asset_tool.main(
                [
                    "--data-bytes", "16",
                    "--seed", "0x89abcdef",
                    "--output", str(output),
                    "--mem-output", str(mem_output),
                ]
            )

            self.assertEqual(result, 0)
            self.assertEqual(output.read_bytes(), asset_tool.build_asset(16, 0x89ABCDEF))
            self.assertEqual(
                mem_output.read_text(encoding="ascii").splitlines(),
                [
                    f"{word:08x}"
                    for word in struct.unpack("<8I", output.read_bytes())
                ],
            )


if __name__ == "__main__":
    unittest.main()
