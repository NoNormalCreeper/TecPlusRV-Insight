#!/usr/bin/env python3
"""通过串口发送最小 GDB RSP packet，验证 target stub 基本闭环。"""

from __future__ import annotations

import argparse
import select
import subprocess
from typing import BinaryIO


PACKET_CAPACITY = 512


class RspError(RuntimeError):
    """GDB RSP framing、checksum 或 transport 错误。"""


def encode_packet(payload: str) -> bytes:
    data = payload.encode("ascii")
    checksum = sum(data) & 0xFF
    return b"$" + data + b"#" + f"{checksum:02x}".encode("ascii")


class RspClient:
    def __init__(self, stream: BinaryIO, timeout: float | None = None):
        self.stream = stream
        self.timeout = timeout

    def _read_byte(self) -> bytes:
        if self.timeout is not None:
            readable, _, _ = select.select([self.stream], [], [], self.timeout)
            if not readable:
                raise RspError("等待 target 字节超时")
        value = self.stream.read(1)
        if value == b"":
            raise RspError("target 提前关闭 transport")
        return value

    def _write(self, data: bytes) -> None:
        written = self.stream.write(data)
        if written != len(data):
            raise RspError("transport 未完整写入 packet")
        self.stream.flush()

    def _read_reply(self) -> str:
        if self._read_byte() != b"$":
            raise RspError("reply 缺少 packet 起始符")

        payload = bytearray()
        while True:
            value = self._read_byte()
            if value == b"#":
                break
            if len(payload) >= PACKET_CAPACITY:
                self._write(b"-")
                raise RspError("reply 超过 PacketSize=200")
            payload.extend(value)

        checksum_text = self._read_byte() + self._read_byte()
        try:
            received_checksum = int(checksum_text, 16)
        except ValueError as exc:
            self._write(b"-")
            raise RspError("reply checksum 不是 hex") from exc

        expected_checksum = sum(payload) & 0xFF
        if received_checksum != expected_checksum:
            self._write(b"-")
            raise RspError(
                f"reply checksum 错误：收到 {received_checksum:02x}，"
                f"期望 {expected_checksum:02x}"
            )

        self._write(b"+")
        try:
            return payload.decode("ascii")
        except UnicodeDecodeError as exc:
            raise RspError("reply payload 不是 ASCII") from exc

    def exchange(self, payload: str) -> str:
        packet = encode_packet(payload)
        for _ in range(3):
            self._write(packet)
            ack = self._read_byte()
            if ack == b"-":
                continue
            if ack != b"+":
                raise RspError(f"target ACK 非法：{ack!r}")
            return self._read_reply()
        raise RspError("target 连续三次 NACK request")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="探测板上 GDB stub 的最小 RSP 闭环")
    parser.add_argument("--port", required=True, help="串口设备，例如 /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=9600, help="串口 baud，默认 9600")
    parser.add_argument("--timeout", type=float, default=2.0, help="单字节等待秒数")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    original = subprocess.check_output(
        ["stty", "-F", args.port, "-g"], text=True
    ).strip()
    subprocess.run(
        ["stty", "-F", args.port, str(args.baud), "raw", "-echo"], check=True
    )

    try:
        with open(args.port, "r+b", buffering=0) as stream:
            client = RspClient(stream, timeout=args.timeout)
            supported = client.exchange("qSupported")
            stop = client.exchange("?")
            registers = client.exchange("g")
            memory = client.exchange("m00000000,10")

            if supported != "PacketSize=200":
                raise RspError(f"qSupported reply 异常：{supported!r}")
            if stop not in {"S04", "S05", "S0b"}:
                raise RspError(f"stop reason 异常：{stop!r}")
            if len(registers) != 264:
                raise RspError(f"g reply 长度={len(registers)}，期望 264")
            if len(memory) != 32:
                raise RspError(f"m reply 长度={len(memory)}，期望 32")

            print(f"qSupported: {supported}")
            print(f"stop: {stop}")
            print(f"register chars: {len(registers)}")
            print(f"memory: {memory}")
            print("PASS: 板上 GDB stub raw RSP probe")
            return 0
    finally:
        subprocess.run(["stty", "-F", args.port, original], check=False)


if __name__ == "__main__":
    raise SystemExit(main())
