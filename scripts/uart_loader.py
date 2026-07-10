#!/usr/bin/env python3
"""把 firmware.bin 封装成 TecPlusRV bootloader v1 数据包并通过 UART 发送。"""

from __future__ import annotations

import argparse
import binascii
import struct
import sys
import time
from pathlib import Path


BOOT_MAGIC = 0xbadabb1e
PROTOCOL_VERSION = 1
COMMAND_LOAD_AND_RUN = 1
BRAM_BYTES = 64 * 1024

RESPONSE_READY = 0x52
RESPONSE_ACK = 0x79
RESPONSE_NACK = 0x1F

ERROR_NAMES = {
    0x00: "无错误",
    0x01: "version 或 command 不支持",
    0x02: "payload 长度非法",
    0x03: "UART framing/overrun",
    0x04: "CRC32 不匹配",
    0x05: "接收超时",
}


def build_packet(payload: bytes) -> tuple[bytes, int]:
    """构造 wire packet；CRC32 不包含 magic。"""
    if not payload:
        raise ValueError("payload 不能为空")
    if len(payload) > BRAM_BYTES:
        raise ValueError(f"payload 超过 64 KiB BRAM：{len(payload)} bytes")

    protocol_header = struct.pack(
        "<BBI", PROTOCOL_VERSION, COMMAND_LOAD_AND_RUN, len(payload)
    )
    crc32 = binascii.crc32(protocol_header + payload) & 0xFFFFFFFF
    packet = struct.pack("<I", BOOT_MAGIC) + protocol_header + payload + struct.pack("<I", crc32)
    return packet, crc32


def wait_response(serial_port, expected: set[int], timeout_seconds: float) -> tuple[int, int]:
    """忽略串口噪声，等待一个已知的两字节 bootloader 响应。"""
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        first = serial_port.read(1)
        if not first or first[0] not in expected:
            continue
        second = serial_port.read(1)
        if second:
            return first[0], second[0]
    raise TimeoutError("等待 bootloader 响应超时")


def send_packet(port_name: str, baud: int, packet: bytes, ready_timeout: float) -> None:
    try:
        import serial  # type: ignore[import-not-found]
    except ImportError as exc:
        raise RuntimeError("真实串口发送需要 pyserial：python3 -m pip install pyserial") from exc

    with serial.Serial(port_name, baudrate=baud, timeout=0.1) as serial_port:
        serial_port.reset_input_buffer()
        print("串口已打开，请按下并松开 TEC-PLUS RESET，等待 bootloader READY...")
        status, code = wait_response(
            serial_port, {RESPONSE_READY, RESPONSE_NACK}, ready_timeout
        )
        if status == RESPONSE_NACK:
            raise RuntimeError(f"bootloader 初始化失败：{ERROR_NAMES.get(code, f'未知错误 0x{code:02x}')}")
        if code != 0:
            raise RuntimeError(f"READY 携带了非法状态码：0x{code:02x}")

        print(f"收到 READY，发送 {len(packet)} bytes...")
        written = serial_port.write(packet)
        if written != len(packet):
            raise RuntimeError(f"串口只写入 {written}/{len(packet)} bytes")
        serial_port.flush()

        status, code = wait_response(
            serial_port, {RESPONSE_ACK, RESPONSE_NACK}, ready_timeout
        )
        if status == RESPONSE_NACK:
            raise RuntimeError(f"下载失败：{ERROR_NAMES.get(code, f'未知错误 0x{code:02x}')}")
        if code != 0:
            raise RuntimeError(f"ACK 携带了非法状态码：0x{code:02x}")
        print("收到 ACK，CPU 已释放并开始运行 payload。")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="TecPlusRV UART bootloader v1 host 工具")
    parser.add_argument("--input", type=Path, default=Path("firmware/build/firmware.bin"))
    parser.add_argument("--port", help="串口名，例如 COM3 或 /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=9600)
    parser.add_argument("--ready-timeout", type=float, default=30.0)
    parser.add_argument("--dry-run", action="store_true", help="只构造并检查数据包，不访问串口")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        payload = args.input.read_bytes()
        packet, crc32 = build_packet(payload)
        print(f"input:   {args.input}")
        print(f"magic:   0x{BOOT_MAGIC:08x} (wire: 1e bb da ba)")
        print(f"version: {PROTOCOL_VERSION}")
        print(f"command: LOAD_AND_RUN ({COMMAND_LOAD_AND_RUN})")
        print(f"payload: {len(payload)} bytes")
        print(f"crc32:   0x{crc32:08x}")
        print(f"packet:  {len(packet)} bytes")

        if args.dry_run:
            print("dry-run 完成，未访问串口。")
            return 0
        if not args.port:
            raise ValueError("真实发送必须提供 --port")
        send_packet(args.port, args.baud, packet, args.ready_timeout)
        return 0
    except (OSError, RuntimeError, TimeoutError, ValueError) as exc:
        print(f"错误：{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
