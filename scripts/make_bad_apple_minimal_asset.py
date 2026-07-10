#!/usr/bin/env python3
"""生成 BAM1 tile/音符原型；真实视频路径复用系统 ffmpeg。"""

from __future__ import annotations

import argparse
import json
import struct
import subprocess
from pathlib import Path


# 最小 bring-up 格式故意使用独立 magic，避免被后续正式 BAP1 parser 误识别。
MAGIC = 0x314D4142  # little-endian "BAM1"
VERSION = 1
COLS = 40
ROWS = 30
WORD_COUNT = COLS * ROWS // 4
FRAME_COUNT = 32
FRAME_PERIOD = 4
HEADER_WORDS = 8
FPS_NUM = 625
FPS_DEN = 42
MIDI_OFFSET_SECONDS = 1.369
MIDI_TIME_SCALE = 1.00218


def _read_varlen(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    while True:
        if offset >= len(data):
            raise ValueError("MIDI variable-length 字段截断")
        byte = data[offset]
        offset += 1
        value = (value << 7) | (byte & 0x7F)
        if byte < 0x80:
            return value, offset


def parse_midi(path: Path) -> dict:
    """解析当前 format-1 MIDI 所需的 tempo、track name 和 note 事件。"""
    data = path.read_bytes()
    if len(data) < 14 or data[:4] != b"MThd":
        raise ValueError("不是 Standard MIDI 文件")
    header_size = int.from_bytes(data[4:8], "big")
    midi_format, track_count, division = struct.unpack(">HHH", data[8:14])
    if midi_format != 1 or division & 0x8000:
        raise ValueError("只支持 PPQN format-1 MIDI")

    offset = 8 + header_size
    tempos: list[tuple[int, int]] = []
    tracks: list[dict] = []
    for _track_index in range(track_count):
        if data[offset : offset + 4] != b"MTrk":
            raise ValueError("MIDI track chunk 缺失")
        size = int.from_bytes(data[offset + 4 : offset + 8], "big")
        track_data = data[offset + 8 : offset + 8 + size]
        offset += 8 + size
        pos = 0
        tick = 0
        running_status = 0
        name = ""
        events: list[tuple[int, int, bool, int]] = []
        event_order = 0
        while pos < len(track_data):
            delta, pos = _read_varlen(track_data, pos)
            tick += delta
            if pos >= len(track_data):
                raise ValueError("MIDI event 截断")
            if track_data[pos] & 0x80:
                status = track_data[pos]
                pos += 1
                if status < 0xF0:
                    running_status = status
                else:
                    running_status = 0
            else:
                if running_status == 0:
                    raise ValueError("MIDI running status 缺少前置状态")
                status = running_status

            if status == 0xFF:
                meta_type = track_data[pos]
                pos += 1
                length, pos = _read_varlen(track_data, pos)
                payload = track_data[pos : pos + length]
                pos += length
                if meta_type == 0x03:
                    name = payload.decode("latin1")
                elif meta_type == 0x51 and length == 3:
                    tempos.append((tick, int.from_bytes(payload, "big")))
                continue
            if status in (0xF0, 0xF7):
                length, pos = _read_varlen(track_data, pos)
                pos += length
                continue

            kind = status & 0xF0
            data_size = 1 if kind in (0xC0, 0xD0) else 2
            if pos + data_size > len(track_data):
                raise ValueError("MIDI channel event 截断")
            note = track_data[pos]
            velocity = track_data[pos + 1] if data_size == 2 else 0
            pos += data_size
            if kind == 0x90 and velocity != 0:
                events.append((tick, event_order, True, note))
                event_order += 1
            elif kind == 0x80 or (kind == 0x90 and velocity == 0):
                events.append((tick, event_order, False, note))
                event_order += 1
        tracks.append({"name": name, "events": events, "end_tick": tick})

    tempo_map = sorted(set(tempos)) or [(0, 500000)]
    max_tick = max((track["end_tick"] for track in tracks), default=0)
    return {
        "format": midi_format,
        "ppqn": division,
        "tempos": tempo_map,
        "tracks": tracks,
        "duration_seconds": _tick_to_seconds(max_tick, division, tempo_map),
    }


def _tick_to_seconds(tick: int, ppqn: int, tempos: list[tuple[int, int]]) -> float:
    seconds = 0.0
    previous_tick = 0
    tempo = 500000
    for tempo_tick, next_tempo in tempos:
        if tempo_tick > tick:
            break
        seconds += (tempo_tick - previous_tick) * tempo / (ppqn * 1_000_000)
        previous_tick = tempo_tick
        tempo = next_tempo
    return seconds + (tick - previous_tick) * tempo / (ppqn * 1_000_000)


def build_midi_frame_events(
    midi: dict,
    *,
    track_name: str,
    clip_start_seconds: float,
    clip_duration_seconds: float,
    transpose: int,
    midi_offset_seconds: float = MIDI_OFFSET_SECONDS,
    midi_time_scale: float = MIDI_TIME_SCALE,
) -> list[tuple[int, int]]:
    """把选定 MIDI 轨道量化为每帧一个单音频率事件。"""
    track = next((item for item in midi["tracks"] if item["name"] == track_name), None)
    if track is None:
        raise ValueError(f"找不到 MIDI track：{track_name}")
    frame_count = round(clip_duration_seconds * FPS_NUM / FPS_DEN)
    active_note: int | None = None
    frame_events: dict[int, int] = {}
    for tick, _order, is_on, note in track["events"]:
        midi_seconds = _tick_to_seconds(tick, midi["ppqn"], midi["tempos"])
        video_seconds = midi_offset_seconds + midi_seconds * midi_time_scale
        if is_on:
            active_note = note
            hz = round(440.0 * 2.0 ** ((note + transpose - 69) / 12.0))
        elif active_note == note:
            active_note = None
            hz = 0
        else:
            continue
        if video_seconds < clip_start_seconds:
            frame_events[0] = hz
        elif video_seconds < clip_start_seconds + clip_duration_seconds:
            frame = round(
                (video_seconds - clip_start_seconds) * FPS_NUM / FPS_DEN
            )
            frame_events[min(frame, frame_count - 1)] = hz

    events: list[tuple[int, int]] = []
    previous_hz = -1
    for frame, hz in sorted(frame_events.items()):
        if hz != previous_hz:
            events.append((frame, hz))
            previous_hz = hz
    return events


def extract_binary_frames(
    video_path: Path, *, start_seconds: float, duration_seconds: float
) -> list[bytes]:
    """用 ffmpeg 抽取真实原片，并把每个像素量化为空格或字符 8。"""
    command = [
        "ffmpeg", "-v", "error", "-ss", str(start_seconds), "-t", str(duration_seconds),
        "-i", str(video_path), "-map", "0:v:0",
        "-vf", f"fps={FPS_NUM}/{FPS_DEN},scale={COLS}:{ROWS}:flags=area,format=gray",
        "-pix_fmt", "gray", "-f", "rawvideo", "pipe:1",
    ]
    result = subprocess.run(command, check=True, capture_output=True)
    frame_bytes = COLS * ROWS
    if len(result.stdout) % frame_bytes:
        raise ValueError("ffmpeg 输出了不完整的视频帧")
    return [
        bytes(ord("8") if value >= 128 else ord(" ") for value in result.stdout[offset : offset + frame_bytes])
        for offset in range(0, len(result.stdout), frame_bytes)
    ]


def write_preview_gif(frames: list[bytes], output: Path) -> None:
    """输出当前 40x30 tile occupancy 原型预览。"""
    output.parent.mkdir(parents=True, exist_ok=True)
    pixels = b"".join(
        bytes(255 if tile != ord(" ") else 0 for tile in frame) for frame in frames
    )
    command = [
        "ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "gray",
        "-s", f"{COLS}x{ROWS}", "-r", f"{FPS_NUM}/{FPS_DEN}", "-i", "pipe:0",
        "-vf", "scale=640:480:flags=neighbor", "-loop", "0", str(output),
    ]
    subprocess.run(command, input=pixels, check=True)


def pack_tiles(tiles: list[int]) -> list[int]:
    return [
        tiles[i] | (tiles[i + 1] << 8) | (tiles[i + 2] << 16) | (tiles[i + 3] << 24)
        for i in range(0, len(tiles), 4)
    ]


def make_frame(frame_index: int) -> list[int]:
    """用现有字模拼一个横向移动的白色轮廓，避免初版依赖视频解码库。"""
    tiles = [ord(" ")] * (COLS * ROWS)
    center = (frame_index * (COLS + 12) // (FRAME_COUNT - 1)) - 6
    for row in range(4, ROWS - 4):
        half_width = 3 + (row * 7 // ROWS)
        left = center - half_width
        right = center + half_width
        for col in (left, right):
            if 0 <= col < COLS:
                tiles[row * COLS + col] = ord("8")
        if row in (4, ROWS - 5):
            for col in range(max(0, left), min(COLS, right + 1)):
                tiles[row * COLS + col] = ord("8")
    return pack_tiles(tiles)


def encode_word_frames(frames: list[list[int]], notes: list[tuple[int, int]]) -> bytes:
    """把 packed tile frames 与单音事件编码成 BAM1。"""
    video_words: list[int] = []
    previous = [0] * WORD_COUNT
    for frame_index, frame in enumerate(frames):
        if frame_index == 0:
            changes = list(enumerate(frame))
        else:
            changes = [(index, value) for index, value in enumerate(frame) if value != previous[index]]
        video_words.append(len(changes))
        for index, value in changes:
            video_words.extend((index, value))
        previous = frame

    video_offset = HEADER_WORDS * 4
    note_offset = video_offset + len(video_words) * 4
    total_bytes = note_offset + len(notes) * 8
    header = [
        MAGIC,
        VERSION,
        total_bytes,
        len(frames),
        video_offset,
        FRAME_PERIOD,
        len(notes),
        note_offset,
    ]
    words = header + video_words
    for frame_index, frequency in notes:
        words.extend((frame_index, frequency))
    return struct.pack(f"<{len(words)}I", *words)


def build_asset() -> bytes:
    """保留小型合成 asset，专供无媒体文件的 RTL regression。"""
    frames = [make_frame(index) for index in range(FRAME_COUNT)]
    notes = [(0, 440), (7, 494), (14, 523), (21, 659), (29, 0)]
    return encode_word_frames(frames, notes)


def build_real_asset(
    video_path: Path,
    midi_path: Path,
    *,
    start_seconds: float,
    duration_seconds: float,
    track_name: str,
    transpose: int,
    midi_offset_seconds: float = MIDI_OFFSET_SECONDS,
    midi_time_scale: float = MIDI_TIME_SCALE,
) -> tuple[bytes, list[bytes], list[tuple[int, int]]]:
    tile_frames = extract_binary_frames(
        video_path, start_seconds=start_seconds, duration_seconds=duration_seconds
    )
    midi = parse_midi(midi_path)
    notes = build_midi_frame_events(
        midi,
        track_name=track_name,
        clip_start_seconds=start_seconds,
        clip_duration_seconds=duration_seconds,
        transpose=transpose,
        midi_offset_seconds=midi_offset_seconds,
        midi_time_scale=midi_time_scale,
    )
    if not tile_frames or not notes:
        raise ValueError("真实短片没有生成视频帧或 MIDI 事件")
    frames = [pack_tiles(list(frame)) for frame in tile_frames]
    data = encode_word_frames(frames, notes)
    validate_player_asset(data)
    return data, tile_frames, notes


def validate_player_asset(data: bytes) -> None:
    if len(data) < HEADER_WORDS * 4 or len(data) % 4:
        raise ValueError("asset 头部不完整或未按 32-bit 对齐")
    magic, version, total_bytes, frame_count, video_offset, _frame_period, note_count, note_offset = struct.unpack_from(
        "<8I", data
    )
    if magic != MAGIC or version != VERSION:
        raise ValueError("asset header magic/version 不匹配")
    if total_bytes != len(data):
        raise ValueError("asset total_bytes 与实际文件大小不一致")
    if frame_count == 0 or frame_count > 1000:
        raise ValueError("asset frame_count 超出 player 上限")
    if note_count > 256:
        raise ValueError("asset note_count 超出 player 上限")
    if len(data) > 1024 * 1024:
        raise ValueError("asset 超过 1 MiB player 上限")
    if video_offset != HEADER_WORDS * 4 or note_offset < video_offset:
        raise ValueError("asset offset 布局非法")


def main() -> int:
    parser = argparse.ArgumentParser(description="生成 Bad Apple 最小 bring-up asset")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("firmware/assets/bad_apple_minimal.bin"),
    )
    parser.add_argument("--mem-output", type=Path, help="可选 32-bit hex 文件，供 RTL 仿真预装")
    parser.add_argument("--video", type=Path, help="真实 MP4 输入；与 --midi 一起提供")
    parser.add_argument("--midi", type=Path, help="真实 MIDI 输入；与 --video 一起提供")
    parser.add_argument("--start", type=float, default=30.0, help="原片截取起点，默认 30 秒")
    parser.add_argument("--duration", type=float, default=20.0, help="截取时长，默认 20 秒")
    parser.add_argument(
        "--midi-track", default="Synth1, Midi name: Bad apple!!", help="单音 MIDI track name"
    )
    parser.add_argument("--transpose", type=int, default=-12, help="MIDI 半音移调，默认 -12")
    parser.add_argument(
        "--midi-offset",
        type=float,
        default=MIDI_OFFSET_SECONDS,
        help="MIDI 到视频的秒级平移，默认使用当前校准值",
    )
    parser.add_argument(
        "--midi-time-scale",
        type=float,
        default=MIDI_TIME_SCALE,
        help="MIDI 到视频的时间缩放，默认使用当前校准值",
    )
    parser.add_argument("--preview", type=Path, help="可选 tile occupancy GIF 预览")
    parser.add_argument("--report", type=Path, help="可选 JSON 转换报告")
    args = parser.parse_args()
    if args.start < 0 or args.duration <= 0 or args.midi_time_scale <= 0:
        raise ValueError("--start 必须非负，--duration 与 --midi-time-scale 必须大于 0")
    if (args.video is None) != (args.midi is None):
        raise ValueError("--video 与 --midi 必须同时提供")

    tile_frames: list[bytes] = []
    notes: list[tuple[int, int]] = []
    midi_info: dict | None = None
    if args.video is not None and args.midi is not None:
        data, tile_frames, notes = build_real_asset(
            args.video,
            args.midi,
            start_seconds=args.start,
            duration_seconds=args.duration,
            track_name=args.midi_track,
            transpose=args.transpose,
            midi_offset_seconds=args.midi_offset,
            midi_time_scale=args.midi_time_scale,
        )
        midi_info = parse_midi(args.midi)
    else:
        data = build_asset()
    validate_player_asset(data)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    if args.mem_output is not None:
        args.mem_output.parent.mkdir(parents=True, exist_ok=True)
        words = list(struct.unpack(f"<{len(data) // 4}I", data))
        # testbench 的固定数组为 4096 words；补零避免 $readmemh 的范围警告。
        if len(words) > 4096:
            raise ValueError("最小 asset 超过 RTL testbench 的 4096-word 上限")
        words.extend([0] * (4096 - len(words)))
        args.mem_output.write_text(
            "".join(f"{word:08x}\n" for word in words), encoding="ascii"
        )
    if args.preview is not None:
        if not tile_frames:
            raise ValueError("--preview 只用于真实视频输入")
        write_preview_gif(tile_frames, args.preview)
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            json.dumps(
                {
                    "video": str(args.video) if args.video else None,
                    "midi": str(args.midi) if args.midi else None,
                    "start_seconds": args.start,
                    "duration_seconds": args.duration,
                    "fps": f"{FPS_NUM}/{FPS_DEN}",
                    "frame_count": len(tile_frames) if tile_frames else FRAME_COUNT,
                    "midi_track": args.midi_track if args.midi else None,
                    "transpose": args.transpose if args.midi else None,
                    "midi_offset_seconds": args.midi_offset if args.midi else None,
                    "midi_time_scale": args.midi_time_scale if args.midi else None,
                    "midi_duration_seconds": midi_info["duration_seconds"] if midi_info else None,
                    "note_event_count": len(notes),
                    "first_note_event": list(notes[0]) if notes else None,
                    "last_note_event": list(notes[-1]) if notes else None,
                    "asset_bytes": len(data),
                    "tile_mode": "40x30 binary space/8 simulation prototype",
                    "future_display": "64x48 1bpp framebuffer；几何由 RTL 综合参数配置，帧率由 asset 的 video_period_ticks 配置",
                },
                ensure_ascii=False,
                indent=2,
            ) + "\n",
            encoding="utf-8",
        )
    frame_count = len(tile_frames) if tile_frames else FRAME_COUNT
    print(f"asset 已生成：{args.output} ({len(data)} bytes, {frame_count} frames)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
