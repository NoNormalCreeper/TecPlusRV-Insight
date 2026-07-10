#!/usr/bin/env python3
"""把 firmware 与可选 SDRAM asset 封装成 TecPlusRV bootloader 数据包。"""

from __future__ import annotations

import argparse
import binascii
import struct
import sys
import threading
import time
from pathlib import Path


BOOT_MAGIC = 0xbadabb1e
PROTOCOL_VERSION = 1
COMMAND_LOAD_AND_RUN = 1
COMMAND_LOAD_IMAGE = 2
BRAM_BYTES = 64 * 1024
SDRAM_BASE_ADDR = 0x80000000
SDRAM_LIMIT_ADDR = 0x82000000
TX_CHUNK_BYTES = 64
DEFAULT_MAX_RETRIES = 5

RESPONSE_READY = 0x52
RESPONSE_ACK = 0x79
RESPONSE_NACK = 0x1F

COLOR_CYAN = "\033[36m"
COLOR_RED = "\033[31m"
COLOR_RESET = "\033[0m"

ERROR_NAMES = {
    0x00: "无错误",
    0x01: "version 或 command 不支持",
    0x02: "payload 长度非法",
    0x03: "UART framing/overrun",
    0x04: "CRC32 不匹配",
    0x05: "接收超时",
    0x06: "SDRAM 写入失败",
}


def host_print(message: str, *, error: bool = False, stream=None) -> None:
    """输出带前缀的 host 提示；非交互输出不附加 ANSI 控制码。"""
    stream = (sys.stderr if error else sys.stdout) if stream is None else stream
    text = f"[loader] {message}"
    if stream.isatty():
        color = COLOR_RED if error else COLOR_CYAN
        text = f"{color}{text}{COLOR_RESET}"
    print(text, file=stream, flush=True)


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


def build_image_packet(
    firmware: bytes, sdram_payload: bytes, sdram_address: int
) -> tuple[bytes, int]:
    """构造 command 2 双段 packet；SDRAM 段按完整 32-bit word 写入。"""
    if not firmware:
        raise ValueError("firmware payload 不能为空")
    if len(firmware) > BRAM_BYTES:
        raise ValueError(f"firmware payload 超过 64 KiB BRAM：{len(firmware)} bytes")
    if not sdram_payload:
        raise ValueError("SDRAM payload 不能为空")
    if len(sdram_payload) % 4:
        raise ValueError("SDRAM payload 长度必须是 4-byte 的整数倍")
    if sdram_address % 4:
        raise ValueError("SDRAM 地址必须 4-byte 对齐")
    if not SDRAM_BASE_ADDR <= sdram_address < SDRAM_LIMIT_ADDR:
        raise ValueError(f"SDRAM 地址不在 0x{SDRAM_BASE_ADDR:08x}..0x{SDRAM_LIMIT_ADDR - 1:08x}")
    if len(sdram_payload) > SDRAM_LIMIT_ADDR - sdram_address:
        raise ValueError("SDRAM payload 超出物理地址窗口")

    protocol_header = struct.pack(
        "<BBIII",
        PROTOCOL_VERSION,
        COMMAND_LOAD_IMAGE,
        len(firmware),
        sdram_address,
        len(sdram_payload),
    )
    body = protocol_header + firmware + sdram_payload
    crc32 = binascii.crc32(body) & 0xFFFFFFFF
    packet = struct.pack("<I", BOOT_MAGIC) + body + struct.pack("<I", crc32)
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


def poll_response(serial_port) -> tuple[int, int] | None:
    """只在至少已有两字节时检查异步 bootloader 响应。"""
    if serial_port.in_waiting < 2:
        return None
    try:
        return wait_response(
            serial_port,
            {RESPONSE_READY, RESPONSE_ACK, RESPONSE_NACK},
            0.2,
        )
    except TimeoutError:
        return None


def transmit_attempt(serial_port, packet: bytes, ready_timeout: float) -> tuple[int, int]:
    """分块发送一次完整 packet，并在块间检查 RESET/NACK。"""
    for offset in range(0, len(packet), TX_CHUNK_BYTES):
        chunk = packet[offset : offset + TX_CHUNK_BYTES]
        written = serial_port.write(chunk)
        if written != len(chunk):
            raise RuntimeError(f"串口只写入 {written}/{len(chunk)} bytes")
        serial_port.flush()

        response = poll_response(serial_port)
        if response is not None:
            return response

    return wait_response(
        serial_port,
        {RESPONSE_READY, RESPONSE_ACK, RESPONSE_NACK},
        ready_timeout,
    )


def transfer_packet(
    serial_port,
    packet: bytes,
    ready_timeout: float,
    max_retries: int,
) -> None:
    """发送 packet；RESET/READY 或 NACK 会触发有限次整包重传。"""
    retries = 0
    while True:
        status, code = transmit_attempt(serial_port, packet, ready_timeout)
        if status == RESPONSE_ACK:
            if code != 0:
                raise RuntimeError(f"ACK 携带了非法状态码：0x{code:02x}")
            return

        if status == RESPONSE_READY and code != 0:
            raise RuntimeError(f"READY 携带了非法状态码：0x{code:02x}")

        if retries >= max_retries:
            if status == RESPONSE_READY:
                reason = "传输期间反复检测到 RESET/READY"
            else:
                reason = ERROR_NAMES.get(code, f"未知错误 0x{code:02x}")
            raise RuntimeError(f"重传次数已用尽：{reason}")

        retries += 1
        serial_port.reset_output_buffer()
        if status == RESPONSE_READY:
            host_print(
                f"传输期间检测到 RESET/READY，从 magic 重新发送 "
                f"({retries}/{max_retries})..."
            )
        else:
            host_print(
                f"收到 NACK：{ERROR_NAMES.get(code, f'未知错误 0x{code:02x}')}，"
                f"整包重传 ({retries}/{max_retries})..."
            )


def monitor_serial(serial_port, output=None, input_stream=None) -> None:
    """保持当前串口连接并把 payload 输出原样转发到终端。"""
    output = sys.stdout.buffer if output is None else output
    input_stream = sys.stdin if input_stream is None else input_stream
    stop_event = threading.Event()

    def wait_for_enter() -> None:
        try:
            input_stream.readline()
        except (OSError, ValueError):
            pass
        finally:
            # Windows Interop 下 Ctrl+C 可能表现为 stdin EOF，而不是
            # KeyboardInterrupt；两种情况都必须结束 monitor。
            stop_event.set()

    threading.Thread(target=wait_for_enter, daemon=True).start()
    host_print("进入 serial monitor，按 Enter 或 Ctrl+C 退出。")
    try:
        while not stop_event.is_set():
            data = serial_port.read(256)
            if data:
                output.write(data)
                output.flush()
    except KeyboardInterrupt:
        print()
        host_print("已退出 serial monitor。")


def send_packet(
    port_name: str,
    baud: int,
    packet: bytes,
    ready_timeout: float,
    monitor: bool = False,
    max_retries: int = DEFAULT_MAX_RETRIES,
) -> None:
    try:
        import serial  # type: ignore[import-not-found]
    except ImportError as exc:
        raise RuntimeError(
            "真实串口发送需要 pyserial：WSL 使用 python3 -m pip install pyserial，"
            "Windows 使用 py -m pip install pyserial"
        ) from exc

    with serial.Serial(port_name, baudrate=baud, timeout=0.1) as serial_port:
        serial_port.reset_input_buffer()
        host_print("串口已打开，请按下并松开 TEC-PLUS RESET，等待 bootloader READY...")
        status, code = wait_response(
            serial_port, {RESPONSE_READY, RESPONSE_NACK}, ready_timeout
        )
        if status == RESPONSE_NACK:
            raise RuntimeError(f"bootloader 初始化失败：{ERROR_NAMES.get(code, f'未知错误 0x{code:02x}')}")
        if code != 0:
            raise RuntimeError(f"READY 携带了非法状态码：0x{code:02x}")

        host_print(
            f"收到 READY，按 {TX_CHUNK_BYTES}-byte chunk 发送 {len(packet)} bytes..."
        )
        transfer_packet(serial_port, packet, ready_timeout, max_retries)
        host_print("收到 ACK，CPU 已释放并开始运行 payload。")
        if monitor:
            monitor_serial(serial_port)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="TecPlusRV UART bootloader host 工具")
    parser.add_argument("--input", type=Path, default=Path("firmware/build/firmware.bin"))
    parser.add_argument("--sdram-input", type=Path, help="可选 SDRAM asset；提供后使用 LOAD_IMAGE")
    parser.add_argument(
        "--sdram-address",
        type=lambda value: int(value, 0),
        default=0x81000000,
        help="SDRAM asset 装载地址，默认 0x81000000",
    )
    parser.add_argument("--port", help="串口名，例如 COM3 或 /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=9600)
    parser.add_argument("--ready-timeout", type=float, default=30.0)
    parser.add_argument(
        "--max-retries",
        type=int,
        default=DEFAULT_MAX_RETRIES,
        help=f"传输被 RESET/NACK 打断后的最大整包重传次数，默认 {DEFAULT_MAX_RETRIES}",
    )
    parser.add_argument(
        "--monitor",
        action="store_true",
        help="上传成功后保持串口连接并持续显示 payload 输出，按 Enter 或 Ctrl+C 退出",
    )
    parser.add_argument("--dry-run", action="store_true", help="只构造并检查数据包，不访问串口")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        payload = args.input.read_bytes()
        asset = None
        if args.sdram_input is not None:
            asset = args.sdram_input.read_bytes()
            if len(asset) % 4:
                asset += bytes(4 - len(asset) % 4)
            packet, crc32 = build_image_packet(payload, asset, args.sdram_address)
        else:
            packet, crc32 = build_packet(payload)
        host_print(f"input:   {args.input}")
        host_print(f"magic:   0x{BOOT_MAGIC:08x} (wire: 1e bb da ba)")
        host_print(f"version: {PROTOCOL_VERSION}")
        if asset is None:
            host_print(f"command: LOAD_AND_RUN ({COMMAND_LOAD_AND_RUN})")
            host_print(f"payload: {len(payload)} bytes")
        else:
            host_print(f"command: LOAD_IMAGE ({COMMAND_LOAD_IMAGE})")
            host_print(f"firmware: {len(payload)} bytes -> BRAM")
            host_print(
                f"asset:    {len(asset)} bytes -> SDRAM 0x{args.sdram_address:08x}"
            )
        host_print(f"crc32:   0x{crc32:08x}")
        host_print(f"packet:  {len(packet)} bytes")

        if args.dry_run:
            host_print("dry-run 完成，未访问串口。")
            return 0
        if not args.port:
            raise ValueError("真实发送必须提供 --port")
        if args.max_retries < 0:
            raise ValueError("--max-retries 不能小于 0")
        send_packet(
            args.port,
            args.baud,
            packet,
            args.ready_timeout,
            monitor=args.monitor,
            max_retries=args.max_retries,
        )
        return 0
    except (OSError, RuntimeError, TimeoutError, ValueError) as exc:
        host_print(f"错误：{exc}", error=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
