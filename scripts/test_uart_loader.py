#!/usr/bin/env python3
"""uart_loader.py 的最小协议一致性测试。"""

from __future__ import annotations

import binascii
import struct
import unittest

import uart_loader


class UartLoaderTest(unittest.TestCase):
    def test_packet_layout_and_crc(self) -> None:
        payload = bytes([0x13, 0x00, 0x00, 0x00, 0x6F, 0x00, 0x00, 0x00])
        packet, crc32 = uart_loader.build_packet(payload)

        self.assertEqual(packet[:4], bytes.fromhex("1e bb da ba"))
        self.assertEqual(packet[4], uart_loader.PROTOCOL_VERSION)
        self.assertEqual(packet[5], uart_loader.COMMAND_LOAD_AND_RUN)
        self.assertEqual(struct.unpack_from("<I", packet, 6)[0], len(payload))
        self.assertEqual(packet[10:-4], payload)
        self.assertEqual(struct.unpack_from("<I", packet, len(packet) - 4)[0], crc32)
        self.assertEqual(crc32, binascii.crc32(packet[4:-4]) & 0xFFFFFFFF)
        self.assertEqual(crc32, 0x065FE657)

    def test_payload_bounds(self) -> None:
        with self.assertRaisesRegex(ValueError, "不能为空"):
            uart_loader.build_packet(b"")
        with self.assertRaisesRegex(ValueError, "超过"):
            uart_loader.build_packet(bytes(uart_loader.BRAM_BYTES + 1))

    def test_full_bram_payload_is_allowed(self) -> None:
        packet, _ = uart_loader.build_packet(bytes(uart_loader.BRAM_BYTES))
        self.assertEqual(len(packet), uart_loader.BRAM_BYTES + 14)


if __name__ == "__main__":
    unittest.main()
