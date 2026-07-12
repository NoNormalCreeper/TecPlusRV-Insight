#!/usr/bin/env python3
"""生成全时长 Bad Apple BAM2 bitmap/MIDI asset。"""

from __future__ import annotations

import argparse
import array
import json
import struct
import subprocess
import sys
import wave
from collections import defaultdict
from pathlib import Path


MAGIC = 0x324D4142  # little-endian "BAM2"
VERSION = 2
HEADER_WORDS = 12
WIDTH = 64
HEIGHT = 48
FRAMEBUFFER_WORDS = WIDTH * HEIGHT // 32
VIDEO_PERIOD_TICKS = 6
VGA_TICKS_NUM = 1250
VGA_TICKS_DEN = 21
VIDEO_FPS_NUM = 625
VIDEO_FPS_DEN = 63
MAX_ASSET_BYTES = 16 * 1024 * 1024
AUDIO_BEAT_FLAG = 1 << 31
ASSET_FLAG_AUDIO_BEATS = 1 << 0
# 与 MP4 开头约 1.370 秒静音精确对齐；不同 tracks 的分层进入不是全局 pre-roll。
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
    """解析 PPQN format-1 MIDI 的 tempo、track 名称与全部音符事件。"""
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
    for track_index in range(track_count):
        if data[offset : offset + 4] != b"MTrk":
            raise ValueError("MIDI track chunk 缺失")
        size = int.from_bytes(data[offset + 4 : offset + 8], "big")
        track_data = data[offset + 8 : offset + 8 + size]
        if len(track_data) != size:
            raise ValueError("MIDI track chunk 截断")
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
                running_status = status if status < 0xF0 else 0
            elif running_status:
                status = running_status
            else:
                raise ValueError("MIDI running status 缺少前置状态")

            if status == 0xFF:
                if pos >= len(track_data):
                    raise ValueError("MIDI meta event 截断")
                meta_type = track_data[pos]
                pos += 1
                length, pos = _read_varlen(track_data, pos)
                payload = track_data[pos : pos + length]
                if len(payload) != length:
                    raise ValueError("MIDI meta payload 截断")
                pos += length
                if meta_type == 0x03:
                    name = payload.decode("latin1")
                elif meta_type == 0x51 and length == 3:
                    tempos.append((tick, int.from_bytes(payload, "big")))
                continue
            if status in (0xF0, 0xF7):
                length, pos = _read_varlen(track_data, pos)
                pos += length
                if pos > len(track_data):
                    raise ValueError("MIDI SysEx payload 截断")
                continue

            kind = status & 0xF0
            data_size = 1 if kind in (0xC0, 0xD0) else 2
            if pos + data_size > len(track_data):
                raise ValueError("MIDI channel event 截断")
            note = track_data[pos]
            velocity = track_data[pos + 1] if data_size == 2 else 0
            pos += data_size
            if kind == 0x90 and velocity:
                events.append((tick, event_order, True, note))
                event_order += 1
            elif kind == 0x80 or (kind == 0x90 and velocity == 0):
                events.append((tick, event_order, False, note))
                event_order += 1
        tracks.append({"index": track_index, "name": name, "events": events,
                       "end_tick": tick})

    tempo_map = sorted(set(tempos)) or [(0, 500000)]
    max_tick = max((track["end_tick"] for track in tracks), default=0)
    return {"format": midi_format, "ppqn": division, "tempos": tempo_map,
            "tracks": tracks,
            "duration_seconds": tick_to_seconds(max_tick, division, tempo_map)}


def tick_to_seconds(tick: int, ppqn: int,
                    tempos: list[tuple[int, int]]) -> float:
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


def note_hz(note: int) -> int:
    return round(440.0 * 2.0 ** ((note - 69) / 12.0))


def build_quarter_note_beats(
    midi: dict,
    *,
    duration_seconds: float,
    offset_seconds: float,
    time_scale: float,
) -> list[int]:
    """按 MIDI PPQ/tempo map 生成与正式音频同时间轴的四分音符 tick。"""
    max_midi_tick = max((track.get("end_tick", 0) for track in midi["tracks"]),
                        default=0)
    beats = []
    for midi_tick in range(0, max_midi_tick + 1, midi["ppqn"]):
        seconds = offset_seconds + tick_to_seconds(
            midi_tick, midi["ppqn"], midi["tempos"]) * time_scale
        if 0.0 <= seconds < duration_seconds:
            vga_tick = round(seconds * VGA_TICKS_NUM / VGA_TICKS_DEN)
            if not beats or beats[-1] != vga_tick:
                beats.append(vga_tick)
    return beats


def clip_beat_ticks(beats: list[int], start_tick: int, end_tick: int) -> list[int]:
    """截取 beat tick；窗口起点本身算作新窗口的 tick 0。"""
    return [tick - start_tick for tick in beats
            if start_tick <= tick < end_tick]


def merge_audio_beats(events: list[tuple[int, int]],
                      beats: list[int]) -> list[tuple[int, int]]:
    """把 beat marker 合入音频事件，并携带该时刻仍然有效的频率。"""
    event_map = dict(events)
    all_ticks = sorted(set(event_map) | set(beats))
    beat_set = set(beats)
    current_hz = 0
    merged = []
    for tick in all_ticks:
        if tick in event_map:
            current_hz = event_map[tick] & ~AUDIO_BEAT_FLAG
        value = current_hz | (AUDIO_BEAT_FLAG if tick in beat_set else 0)
        merged.append((tick, value))
    return merged


def _track_priority(name: str) -> int | None:
    lower = name.lower()
    # 鼓件 note number 表示乐器种类，bass 音域也不适合单路方波；宁可静音也不伪装成旋律。
    if any(token in lower for token in ("drum", "perc", "bass")):
        return None
    for priority, token in enumerate(("synth1", "vocals", "guitar", "arp", "synth2")):
        if token in lower:
            return priority
    return 20


def _track_note_shift(name: str) -> int:
    """把低音域的 Synth2 前奏提高两组八度，其他旋律轨沿用全局 transpose。"""
    return 24 if "synth2" in name.lower() else 0


def fold_note_to_range(note: int, minimum: int, maximum: int) -> int:
    """按八度折叠音高，保留音名并避开 buzzer 的过低/过高区。"""
    while note < minimum:
        note += 12
    while note > maximum:
        note -= 12
    return note


def build_all_track_events(
    midi: dict,
    *,
    duration_seconds: float,
    offset_seconds: float = MIDI_OFFSET_SECONDS,
    time_scale: float = MIDI_TIME_SCALE,
    transpose: int = -12,
) -> list[tuple[int, int]]:
    """把全部 MIDI tracks 归约为不丢单轨区段的单音 VGA-tick 事件。"""
    grouped: dict[int, list[tuple[int, int, bool, int]]] = defaultdict(list)
    for track_index, track in enumerate(midi["tracks"]):
        for tick, order, is_on, note in track["events"]:
            grouped[tick].append((track_index, order, is_on, note))

    active: list[list[tuple[int, int]]] = [[] for _ in midi["tracks"]]
    serial = 0
    tick_frequencies: dict[int, int] = {}
    for midi_tick in sorted(grouped):
        # 同 tick 内先释放再按原顺序按下，避免产生量化后的伪静音。
        events = sorted(grouped[midi_tick], key=lambda item: (item[2], item[1]))
        for track_index, _order, is_on, note in events:
            notes = active[track_index]
            if is_on:
                serial += 1
                notes.append((note, serial))
            else:
                for index in range(len(notes) - 1, -1, -1):
                    if notes[index][0] == note:
                        del notes[index]
                        break

        selected: tuple[int, int, int] | None = None
        for track_index, notes in enumerate(active):
            if not notes:
                continue
            priority = _track_priority(midi["tracks"][track_index]["name"])
            if priority is None:
                continue
            note, note_serial = max(notes, key=lambda item: item[1])
            candidate = (priority, -note_serial,
                         note + _track_note_shift(midi["tracks"][track_index]["name"]))
            if selected is None or candidate < selected:
                selected = candidate
        hz = 0 if selected is None else note_hz(selected[2] + transpose)
        seconds = offset_seconds + tick_to_seconds(
            midi_tick, midi["ppqn"], midi["tempos"]) * time_scale
        vga_tick = round(seconds * VGA_TICKS_NUM / VGA_TICKS_DEN)
        if vga_tick < 0:
            tick_frequencies[0] = hz
        elif seconds < duration_seconds:
            tick_frequencies[vga_tick] = hz

    events: list[tuple[int, int]] = []
    previous_hz = -1
    for vga_tick, hz in sorted(tick_frequencies.items()):
        if not events and hz == 0:
            previous_hz = 0
            continue
        if hz != previous_hz:
            events.append((vga_tick, hz))
            previous_hz = hz
    return events


def build_compact_piano_events(
    midi: dict,
    *,
    duration_seconds: float,
    offset_seconds: float,
    time_scale: float,
    transpose: int,
    source_track_index: int = 2,
    rhythm_track_index: int = 3,
) -> list[tuple[int, int]]:
    """归约两轨钢琴版：低音和弦变 click，高音复音取较低的主旋律音。"""
    if source_track_index >= len(midi["tracks"]):
        raise ValueError("compact piano MIDI 缺少主 track")
    melody_onsets = [tick for tick, _order, is_on, note
                     in midi["tracks"][source_track_index]["events"]
                     if is_on and note >= 60]
    melody_first_tick = min(melody_onsets) if melody_onsets else None
    melody_last_tick = max(melody_onsets) if melody_onsets else None
    long_melody_gaps: list[tuple[int, int]] = []
    for previous, current in zip(melody_onsets, melody_onsets[1:]):
        gap_seconds = tick_to_seconds(current, midi["ppqn"], midi["tempos"]) - \
            tick_to_seconds(previous, midi["ppqn"], midi["tempos"])
        if gap_seconds >= 4.0:
            long_melody_gaps.append((previous, current))
    grouped: dict[int, list[tuple[int, int, bool, int]]] = defaultdict(list)
    for tick, order, is_on, note in midi["tracks"][source_track_index]["events"]:
        grouped[tick].append((source_track_index, order, is_on, note))
    if rhythm_track_index < len(midi["tracks"]):
        for tick, order, is_on, note in midi["tracks"][rhythm_track_index]["events"]:
            grouped[tick].append((rhythm_track_index, order, is_on, note))
    active: list[int] = []
    tick_frequencies: dict[int, int] = {}

    def schedule_drum(vga_tick: int, frequencies: tuple[int, int, int]) -> None:
        for step, hz in enumerate(frequencies):
            tick_frequencies[vga_tick + step] = hz
        tick_frequencies[vga_tick + len(frequencies)] = 0

    for midi_tick in sorted(grouped):
        current = sorted(grouped[midi_tick], key=lambda event: (event[2], event[1]))
        source_onsets = [note for track, _order, is_on, note in current
                         if track == source_track_index and is_on]
        rhythm_onsets = [note for track, _order, is_on, note in current
                         if track == rhythm_track_index and is_on]
        source_event_present = any(track == source_track_index
                                   for track, _order, _is_on, _note in current)
        for track, _order, is_on, note in current:
            if track != source_track_index:
                continue
            if is_on:
                active.append(note)
            else:
                for index in range(len(active) - 1, -1, -1):
                    if active[index] == note:
                        del active[index]
                        break
        seconds = offset_seconds + tick_to_seconds(
            midi_tick, midi["ppqn"], midi["tempos"]) * time_scale
        if seconds < 0 or seconds >= duration_seconds:
            continue
        vga_tick = round(seconds * VGA_TICKS_NUM / VGA_TICKS_DEN)
        melody = [note for note in active if note >= 60]
        rhythm_allowed = (melody_first_tick is None or
                          midi_tick < melody_first_tick or
                          midi_tick > melody_last_tick)
        interlude_fallback = any(start < midi_tick < end
                                 for start, end in long_melody_gaps)
        if melody:
            tick_frequencies[vga_tick] = note_hz(min(melody) + transpose)
        elif interlude_fallback and rhythm_onsets:
            # 长间奏才使用伴奏最高音；额外提高两组八度，抵消全局降八度并避开低频。
            fallback_note = fold_note_to_range(
                max(rhythm_onsets) + transpose + 24, 52, 76)
            tick_frequencies[vga_tick] = note_hz(fallback_note)
        elif rhythm_allowed and source_onsets and max(source_onsets) < 60:
            # 三段降频包络比固定短方波更接近 kick/tom；四音以上使用较强 accent。
            schedule_drum(vga_tick, (360, 220, 120) if len(set(source_onsets)) >= 4
                          else (180, 110, 70))
        elif rhythm_allowed and rhythm_onsets:
            schedule_drum(vga_tick, (240, 140, 80))
        elif not active and source_event_present:
            tick_frequencies[vga_tick] = 0
    events: list[tuple[int, int]] = []
    previous_hz = -1
    max_tick = round(duration_seconds * VGA_TICKS_NUM / VGA_TICKS_DEN)
    for vga_tick, hz in sorted(tick_frequencies.items()):
        if vga_tick >= max_tick:
            continue
        if not events and hz == 0:
            previous_hz = 0
            continue
        if hz != previous_hz:
            events.append((vga_tick, hz))
            previous_hz = hz
    return events


def clip_audio_events(events: list[tuple[int, int]], start_tick: int,
                      end_tick: int) -> list[tuple[int, int]]:
    """截取音频事件，并把截点前仍 active 的频率带到新 tick 0。"""
    active_hz = 0
    for tick, hz in events:
        if tick > start_tick:
            break
        active_hz = hz
    clipped = [(0, active_hz)] if active_hz else []
    for tick, hz in events:
        if start_tick < tick < end_tick:
            relative = (tick - start_tick, hz)
            if not clipped or clipped[-1][1] != hz:
                clipped.append(relative)
    return clipped


def extract_bitmap_frames(video: Path, *, start_seconds: float,
                          duration_seconds: float) -> list[list[int]]:
    command = [
        "ffmpeg", "-v", "error", "-ss", str(start_seconds), "-t",
        str(duration_seconds), "-i", str(video), "-map", "0:v:0", "-vf",
        f"fps={VIDEO_FPS_NUM}/{VIDEO_FPS_DEN},scale={WIDTH}:{HEIGHT}:flags=area,format=gray",
        "-pix_fmt", "gray", "-f", "rawvideo", "pipe:1",
    ]
    raw = subprocess.run(command, check=True, capture_output=True).stdout
    frame_bytes = WIDTH * HEIGHT
    if len(raw) % frame_bytes:
        raise ValueError("ffmpeg 输出了不完整的视频帧")
    frames = []
    for base in range(0, len(raw), frame_bytes):
        pixels = raw[base : base + frame_bytes]
        words = []
        for word_base in range(0, frame_bytes, 32):
            word = 0
            for bit, value in enumerate(pixels[word_base : word_base + 32]):
                if value >= 128:
                    word |= 1 << bit
            words.append(word)
        frames.append(words)
    return frames


def encode_asset(frames: list[list[int]], audio_events: list[tuple[int, int]],
                 *, duration_ticks: int) -> bytes:
    if not frames or any(len(frame) != FRAMEBUFFER_WORDS for frame in frames):
        raise ValueError("每帧必须恰好包含 96 words")
    video_words: list[int] = []
    previous = [0] * FRAMEBUFFER_WORDS
    for frame_index, frame in enumerate(frames):
        changes = (list(enumerate(frame)) if frame_index == 0 else
                   [(index, word) for index, word in enumerate(frame)
                    if word != previous[index]])
        video_words.append(len(changes))
        for index, word in changes:
            video_words.extend((index, word))
        previous = frame
    video_offset = HEADER_WORDS * 4
    audio_offset = video_offset + len(video_words) * 4
    total_bytes = audio_offset + len(audio_events) * 8
    if total_bytes > MAX_ASSET_BYTES:
        raise ValueError(f"asset 超过 16 MiB 上限：{total_bytes} bytes")
    flags = (ASSET_FLAG_AUDIO_BEATS if any(value & AUDIO_BEAT_FLAG
                                           for _tick, value in audio_events) else 0)
    words = [MAGIC, VERSION, total_bytes, duration_ticks, len(frames),
             video_offset, VIDEO_PERIOD_TICKS, len(audio_events), audio_offset,
             FRAMEBUFFER_WORDS, flags, 0] + video_words
    for tick, hz in audio_events:
        words.extend((tick, hz))
    return struct.pack(f"<{len(words)}I", *words)


def validate_asset(data: bytes) -> dict:
    if len(data) < HEADER_WORDS * 4 or len(data) % 4:
        raise ValueError("BAM2 头部不完整或未按 word 对齐")
    header = struct.unpack_from("<12I", data)
    (magic, version, total_bytes, duration_ticks, frame_count, video_offset,
     period, audio_count, audio_offset, framebuffer_words, flags,
     reserved) = header
    if (magic, version) != (MAGIC, VERSION) or total_bytes != len(data):
        raise ValueError("BAM2 magic/version/size 不匹配")
    if framebuffer_words != FRAMEBUFFER_WORDS or period != VIDEO_PERIOD_TICKS:
        raise ValueError("BAM2 framebuffer 或 period 不匹配")
    if flags & ~ASSET_FLAG_AUDIO_BEATS or reserved or video_offset != HEADER_WORDS * 4:
        raise ValueError("BAM2 reserved/header offset 不匹配")
    if audio_offset < video_offset or audio_offset + audio_count * 8 != len(data):
        raise ValueError("BAM2 audio stream 边界不匹配")
    words = struct.unpack(f"<{len(data) // 4}I", data)
    cursor = video_offset // 4
    audio_word = audio_offset // 4
    current = [0] * FRAMEBUFFER_WORDS
    frames = []
    for frame_index in range(frame_count):
        if cursor >= audio_word:
            raise ValueError("BAM2 video record 截断")
        count = words[cursor]
        cursor += 1
        if frame_index == 0 and count != FRAMEBUFFER_WORDS:
            raise ValueError("BAM2 第一帧不是 full frame")
        if cursor + count * 2 > audio_word:
            raise ValueError("BAM2 video changes 越界")
        for _ in range(count):
            index, value = words[cursor], words[cursor + 1]
            cursor += 2
            if index >= FRAMEBUFFER_WORDS:
                raise ValueError("BAM2 framebuffer word index 越界")
            current[index] = value
        frames.append(current.copy())
    if cursor != audio_word:
        raise ValueError("BAM2 video stream 未精确结束")
    audio = [(words[audio_word + index * 2], words[audio_word + index * 2 + 1])
             for index in range(audio_count)]
    if any(audio[index][0] <= audio[index - 1][0] for index in range(1, len(audio))):
        raise ValueError("BAM2 audio tick 不是严格递增")
    if audio and audio[-1][0] >= duration_ticks:
        raise ValueError("BAM2 audio event 超出总时长")
    if any(value & AUDIO_BEAT_FLAG for _tick, value in audio) and not (
            flags & ASSET_FLAG_AUDIO_BEATS):
        raise ValueError("BAM2 beat marker 缺少 header flag")
    return {"total_bytes": total_bytes, "duration_vga_ticks": duration_ticks,
            "frame_count": frame_count, "audio_event_count": audio_count,
            "flags": flags, "decoded_frames": frames,
            "decoded_audio_events": audio}


def probe_video_duration(path: Path) -> float:
    command = ["ffprobe", "-v", "error", "-select_streams", "v:0",
               "-show_entries", "stream=duration", "-of",
               "default=noprint_wrappers=1:nokey=1", str(path)]
    return float(subprocess.run(command, check=True, capture_output=True,
                                text=True).stdout.strip())


def write_mem(data: bytes, path: Path) -> None:
    words = struct.unpack(f"<{len(data) // 4}I", data)
    path.write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")


def write_buzzer_wav(data: bytes, output, *, sample_rate: int = 44100) -> None:
    """按 BAM2 event 时间轴生成接近板上单路方波 buzzer 的 mono WAV。"""
    if sample_rate <= 0:
        raise ValueError("preview sample rate 必须大于 0")
    checked = validate_asset(data)
    duration_ticks = checked["duration_vga_ticks"]
    events = checked["decoded_audio_events"]
    total_samples = round(duration_ticks * VGA_TICKS_DEN / VGA_TICKS_NUM * sample_rate)
    samples = array.array("h")
    event_index = 0
    hz = 0
    phase = 0.0
    for sample_index in range(total_samples):
        tick = sample_index * VGA_TICKS_NUM / (sample_rate * VGA_TICKS_DEN)
        while event_index < len(events) and events[event_index][0] <= tick:
            hz = events[event_index][1] & ~AUDIO_BEAT_FLAG
            event_index += 1
        if hz:
            samples.append(10000 if phase < 0.5 else -10000)
            phase = (phase + hz / sample_rate) % 1.0
        else:
            samples.append(0)
            phase = 0.0
    if sys.byteorder != "little":
        samples.byteswap()
    wave_output = str(output) if isinstance(output, Path) else output
    with wave.open(wave_output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(samples.tobytes())


def write_preview_mp4(data: bytes, audio_path: Path, output_path: Path) -> None:
    """把最终 BAM2 frames 与方波 WAV 合成为板级几何预览。"""
    frames = validate_asset(data)["decoded_frames"]
    pixels = bytearray()
    for frame in frames:
        for word in frame:
            pixels.extend(255 if word & (1 << bit) else 0 for bit in range(32))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    command = [
        "ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "gray",
        "-s", f"{WIDTH}x{HEIGHT}", "-framerate",
        f"{VIDEO_FPS_NUM}/{VIDEO_FPS_DEN}", "-i", "pipe:0", "-i", str(audio_path),
        "-vf", "scale=512:384:flags=neighbor,pad=640:480:64:48:black",
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-shortest",
        str(output_path),
    ]
    subprocess.run(command, input=bytes(pixels), check=True)


def write_preview_outputs(data: bytes, audio_path: Path | None,
                          preview_path: Path | None) -> None:
    if preview_path is not None and audio_path is None:
        audio_path = preview_path.with_suffix(".wav")
    if audio_path is not None:
        audio_path.parent.mkdir(parents=True, exist_ok=True)
        write_buzzer_wav(data, audio_path)
    if preview_path is not None:
        write_preview_mp4(data, audio_path, preview_path)


def build_synthetic_asset() -> bytes:
    """生成短小但覆盖 full frame、delta、换音与静音的 RTL asset。"""
    first = [0] * FRAMEBUFFER_WORDS
    first[0] = 0xFFFFFFFF
    second = first.copy()
    second[1] = 0x80000001
    third = second.copy()
    third[0] = 0
    third[95] = 0xFFFFFFFF
    # 72 ticks 超过 1 秒，端到端仿真可同时验证每秒 UART 进度。
    audio = merge_audio_beats([(0, 440), (7, 494), (14, 0)], [0, 20, 40, 60])
    return encode_asset([first, second, third], audio,
                        duration_ticks=72)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", type=Path)
    parser.add_argument("--midi", type=Path)
    parser.add_argument("--synthetic", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--preview-input", type=Path,
                        help="只预览已有 BAM2，不重新转换媒体")
    parser.add_argument("--mem", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--preview", type=Path, help="输出带模拟 buzzer 音频的 MP4")
    parser.add_argument("--preview-audio", type=Path, help="输出模拟 buzzer mono WAV")
    parser.add_argument("--start", type=float, default=0.0)
    parser.add_argument("--duration", type=float)
    parser.add_argument("--transpose", type=int, default=-12)
    parser.add_argument("--midi-offset", type=float, default=MIDI_OFFSET_SECONDS)
    parser.add_argument("--midi-time-scale", type=float, default=MIDI_TIME_SCALE)
    parser.add_argument("--midi-mode", choices=("multitrack", "compact-piano"),
                        default="multitrack")
    parser.add_argument("--midi-tail-align", type=float,
                        help="把 MIDI 完整结束时间对齐到指定视频秒数")
    args = parser.parse_args()
    if args.preview_input is not None:
        if args.output or args.video or args.midi or args.synthetic:
            raise ValueError("--preview-input 不能与资源生成参数同时使用")
        if args.preview is None and args.preview_audio is None:
            raise ValueError("--preview-input 必须指定 --preview 或 --preview-audio")
        data = args.preview_input.read_bytes()
        validate_asset(data)
        write_preview_outputs(data, args.preview_audio, args.preview)
        return
    if args.output is None:
        raise ValueError("资源生成必须指定 --output")
    if args.synthetic:
        if args.video or args.midi:
            raise ValueError("--synthetic 不能与 --video/--midi 同时使用")
        data = build_synthetic_asset()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(data)
        if args.mem:
            args.mem.parent.mkdir(parents=True, exist_ok=True)
            write_mem(data, args.mem)
        report = validate_asset(data)
        report = {key: value for key, value in report.items()
                  if not key.startswith("decoded_")}
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                                   encoding="utf-8")
        write_preview_outputs(data, args.preview_audio, args.preview)
        print(json.dumps(report, ensure_ascii=False))
        return
    if args.video is None or args.midi is None:
        raise ValueError("真实资源必须同时提供 --video 与 --midi")
    full_duration = probe_video_duration(args.video)
    duration = args.duration if args.duration is not None else full_duration - args.start
    if args.start < 0 or duration <= 0 or args.start + duration > full_duration + 0.01:
        raise ValueError("视频 start/duration 超出范围")
    frames = extract_bitmap_frames(args.video, start_seconds=args.start,
                                   duration_seconds=duration)
    midi = parse_midi(args.midi)
    midi_offset = (args.midi_tail_align - midi["duration_seconds"] * args.midi_time_scale
                   if args.midi_tail_align is not None else args.midi_offset)
    if args.midi_mode == "compact-piano":
        audio = build_compact_piano_events(
            midi, duration_seconds=args.start + duration, offset_seconds=midi_offset,
            time_scale=args.midi_time_scale, transpose=args.transpose)
    else:
        audio = build_all_track_events(
            midi, duration_seconds=args.start + duration, offset_seconds=midi_offset,
            time_scale=args.midi_time_scale, transpose=args.transpose)
    beats = build_quarter_note_beats(
        midi, duration_seconds=args.start + duration, offset_seconds=midi_offset,
        time_scale=args.midi_time_scale)
    duration_ticks = len(frames) * VIDEO_PERIOD_TICKS
    start_tick = round(args.start * VGA_TICKS_NUM / VGA_TICKS_DEN)
    audio = clip_audio_events(audio, start_tick, start_tick + duration_ticks)
    beats = clip_beat_ticks(beats, start_tick, start_tick + duration_ticks)
    audio = merge_audio_beats(audio, beats)
    data = encode_asset(frames, audio, duration_ticks=duration_ticks)
    checked = validate_asset(data)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    if args.mem:
        args.mem.parent.mkdir(parents=True, exist_ok=True)
        write_mem(data, args.mem)
    track_notes = {track["name"] or f"track-{track.get('index', index)}":
                   sum(1 for event in track["events"] if event[2])
                   for index, track in enumerate(midi["tracks"]) if track["events"]}
    report = {key: value for key, value in checked.items()
              if not key.startswith("decoded_")}
    report.update({"video": str(args.video), "midi": str(args.midi),
                   "start_seconds": args.start, "requested_duration_seconds": duration,
                   "playback_duration_seconds": duration_ticks * VGA_TICKS_DEN / VGA_TICKS_NUM,
                   "midi_mode": args.midi_mode,
                   "midi_offset_seconds": midi_offset,
                   "midi_time_scale": args.midi_time_scale,
                   "beat_count": len(beats),
                   "track_note_on_counts": track_notes,
                   "estimated_upload_seconds_115200": len(data) * 10 / 115200})
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                               encoding="utf-8")
    write_preview_outputs(data, args.preview_audio, args.preview)
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
