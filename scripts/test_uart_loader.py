#!/usr/bin/env python3
"""uart_loader.py 的最小协议一致性测试。"""

from __future__ import annotations

import binascii
import contextlib
import io
import struct
import threading
import unittest

import uart_loader


class UartLoaderTest(unittest.TestCase):
    def test_ready_during_transfer_restarts_from_magic(self) -> None:
        packet, _ = uart_loader.build_packet(bytes(range(136)))

        class FakeSerial:
            def __init__(self) -> None:
                self.attempts = [bytearray()]
                self.rx = bytearray()
                self.output_resets = 0

            @property
            def in_waiting(self) -> int:
                return len(self.rx)

            def write(self, data: bytes) -> int:
                self.attempts[-1].extend(data)
                return len(data)

            def flush(self) -> None:
                if len(self.attempts) == 1 and not self.rx:
                    self.rx.extend((uart_loader.RESPONSE_READY, 0))
                elif len(self.attempts) == 2 and len(self.attempts[-1]) == len(packet):
                    self.rx.extend((uart_loader.RESPONSE_ACK, 0))

            def read(self, size: int) -> bytes:
                data = bytes(self.rx[:size])
                del self.rx[:size]
                return data

            def reset_output_buffer(self) -> None:
                self.output_resets += 1
                self.attempts.append(bytearray())

        serial_port = FakeSerial()
        with contextlib.redirect_stdout(io.StringIO()):
            uart_loader.transfer_packet(serial_port, packet, 0.1, max_retries=3)

        self.assertEqual(bytes(serial_port.attempts[0]), packet[:64])
        self.assertEqual(bytes(serial_port.attempts[1]), packet)
        self.assertEqual(serial_port.output_resets, 1)

    def test_repeated_ready_eventually_fails(self) -> None:
        class ResettingSerial:
            def __init__(self) -> None:
                self.rx = bytearray()

            @property
            def in_waiting(self) -> int:
                return len(self.rx)

            def write(self, data: bytes) -> int:
                return len(data)

            def flush(self) -> None:
                self.rx.extend((uart_loader.RESPONSE_READY, 0))

            def read(self, size: int) -> bytes:
                data = bytes(self.rx[:size])
                del self.rx[:size]
                return data

            def reset_output_buffer(self) -> None:
                pass

        with self.assertRaisesRegex(RuntimeError, "重传次数已用尽"):
            with contextlib.redirect_stdout(io.StringIO()):
                uart_loader.transfer_packet(
                    ResettingSerial(), b"payload", 0.1, max_retries=1
                )

    def test_host_messages_use_color_only_on_tty(self) -> None:
        class TtyStream(io.StringIO):
            def isatty(self) -> bool:
                return True

        tty_output = TtyStream()
        uart_loader.host_print("测试提示", stream=tty_output)
        self.assertEqual(
            tty_output.getvalue(),
            "\033[36m[loader] 测试提示\033[0m\n",
        )

        redirected_output = io.StringIO()
        uart_loader.host_print("测试提示", stream=redirected_output)
        self.assertEqual(redirected_output.getvalue(), "[loader] 测试提示\n")

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

    def test_image_packet_layout_and_crc(self) -> None:
        firmware = b"\x13\x00\x00\x00"
        asset = b"BAD!"
        packet, crc32 = uart_loader.build_image_packet(
            firmware, asset, 0x81000000
        )

        self.assertEqual(packet[:4], bytes.fromhex("1e bb da ba"))
        self.assertEqual(packet[4], uart_loader.PROTOCOL_VERSION)
        self.assertEqual(packet[5], uart_loader.COMMAND_LOAD_IMAGE)
        self.assertEqual(struct.unpack_from("<I", packet, 6)[0], len(firmware))
        self.assertEqual(struct.unpack_from("<I", packet, 10)[0], 0x81000000)
        self.assertEqual(struct.unpack_from("<I", packet, 14)[0], len(asset))
        self.assertEqual(packet[18:-4], firmware + asset)
        self.assertEqual(crc32, binascii.crc32(packet[4:-4]) & 0xFFFFFFFF)

    def test_image_packet_rejects_unaligned_asset(self) -> None:
        with self.assertRaisesRegex(ValueError, "4-byte"):
            uart_loader.build_image_packet(b"firmware", b"abc", 0x81000000)

    def test_monitor_forwards_bytes_until_ctrl_c(self) -> None:
        class BlockingInput:
            def readline(self) -> str:
                threading.Event().wait()
                return ""

        class FakeSerial:
            def __init__(self) -> None:
                self.responses = iter((b"payload ready\r\n", b"\xff", KeyboardInterrupt()))

            def read(self, _size: int) -> bytes:
                response = next(self.responses)
                if isinstance(response, BaseException):
                    raise response
                return response

        output = io.BytesIO()
        messages = io.StringIO()
        with contextlib.redirect_stdout(messages):
            uart_loader.monitor_serial(FakeSerial(), output, BlockingInput())

        self.assertEqual(output.getvalue(), b"payload ready\r\n\xff")
        self.assertIn("Ctrl+C", messages.getvalue())
        self.assertNotIn("\033[", output.getvalue().decode("latin1"))

    def test_monitor_can_exit_with_enter(self) -> None:
        first_read = threading.Event()

        class FakeSerial:
            def read(self, _size: int) -> bytes:
                first_read.set()
                return b"payload output\r\n"

        class EnterAfterFirstRead:
            def readline(self) -> str:
                first_read.wait()
                return "\n"

        output = io.BytesIO()
        with contextlib.redirect_stdout(io.StringIO()):
            uart_loader.monitor_serial(FakeSerial(), output, EnterAfterFirstRead())

        self.assertTrue(output.getvalue().startswith(b"payload output\r\n"))

    def test_monitor_exits_when_interop_closes_stdin(self) -> None:
        class FakeSerial:
            def read(self, _size: int) -> bytes:
                return b""

        output = io.BytesIO()
        with contextlib.redirect_stdout(io.StringIO()):
            uart_loader.monitor_serial(FakeSerial(), output, io.StringIO(""))

        self.assertEqual(output.getvalue(), b"")

    def test_monitor_argument(self) -> None:
        args = uart_loader.parse_args(["--monitor"])
        self.assertTrue(args.monitor)


if __name__ == "__main__":
    unittest.main()
