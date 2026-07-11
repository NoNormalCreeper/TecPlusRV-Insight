#!/usr/bin/env python3
"""从 Bad Apple 原视频混合音轨提取单音 pitch，并生成 buzzer 方波试听。"""

from __future__ import annotations

import argparse
import json
import subprocess
import wave
from pathlib import Path

import numpy as np
from scipy.signal import medfilt


ANALYSIS_RATE = 8000
OUTPUT_RATE = 44100
FRAME_SIZE = 2048
HOP_SIZE = 128
MIN_MIDI = 40
MAX_MIDI = 88


def decode_audio(path: Path, sample_rate: int = ANALYSIS_RATE) -> np.ndarray:
    command = [
        "ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0", "-ac", "1",
        "-ar", str(sample_rate), "-af", "highpass=f=70,lowpass=f=1800",
        "-f", "f32le", "pipe:1",
    ]
    raw = subprocess.run(command, check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").copy()


def extract_pitch_track(samples: np.ndarray, sample_rate: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """用 harmonic summation 把混合音频压成逐 hop 的 12-TET 单音轨。"""
    if sample_rate <= 0 or samples.ndim != 1:
        raise ValueError("pitch 输入必须是有效的 mono PCM")
    if len(samples) < FRAME_SIZE:
        samples = np.pad(samples, (0, FRAME_SIZE - len(samples)))
    frame_count = 1 + (len(samples) - FRAME_SIZE) // HOP_SIZE
    times = np.arange(frame_count, dtype=np.float64) * HOP_SIZE / sample_rate
    notes = np.full(frame_count, -1, dtype=np.int16)
    confidence = np.zeros(frame_count, dtype=np.float32)
    window = np.hanning(FRAME_SIZE).astype(np.float32)
    candidates = np.arange(MIN_MIDI, MAX_MIDI + 1)
    frequencies = 440.0 * 2.0 ** ((candidates - 69) / 12.0)
    fft_frequencies = np.fft.rfftfreq(FRAME_SIZE, 1.0 / sample_rate)
    harmonic_bins = []
    harmonic_weights = []
    for harmonic, weight in ((1, 1.0), (2, 0.55), (3, 0.35), (4, 0.25)):
        target = frequencies * harmonic
        harmonic_bins.append(np.searchsorted(fft_frequencies, target).clip(0, len(fft_frequencies) - 1))
        harmonic_weights.append(weight)

    for index in range(frame_count):
        start = index * HOP_SIZE
        frame = samples[start : start + FRAME_SIZE]
        rms = float(np.sqrt(np.mean(frame * frame)))
        if rms < 0.003:
            continue
        magnitude = np.abs(np.fft.rfft(frame * window))
        scores = np.zeros(len(candidates), dtype=np.float64)
        for bins, weight in zip(harmonic_bins, harmonic_weights):
            scores += magnitude[bins] * weight
        best = int(np.argmax(scores))
        notes[index] = int(candidates[best])
        confidence[index] = float(scores[best] / (np.sum(magnitude) + 1e-12))

    # 约 80 ms median 抑制混合音轨中瞬时鼓点造成的跳音；静音保持静音。
    voiced = notes >= 0
    filled = notes.copy()
    if np.any(voiced):
        last = int(notes[np.flatnonzero(voiced)[0]])
        for index in range(len(filled)):
            if filled[index] >= 0:
                last = int(filled[index])
            else:
                filled[index] = last
        smoothed = medfilt(filled, kernel_size=5).astype(np.int16)
        notes[voiced] = smoothed[voiced]
    return times, notes, confidence


def synthesize_square(notes: np.ndarray, duration_seconds: float,
                      output_rate: int = OUTPUT_RATE) -> np.ndarray:
    total_samples = round(duration_seconds * output_rate)
    output = np.zeros(total_samples, dtype=np.int16)
    phase = 0.0
    samples_per_hop = HOP_SIZE / ANALYSIS_RATE * output_rate
    for index, note in enumerate(notes):
        start = round(index * samples_per_hop)
        end = min(total_samples, round((index + 1) * samples_per_hop))
        if start >= total_samples or note < 0:
            phase = 0.0
            continue
        hz = 440.0 * 2.0 ** ((int(note) - 69) / 12.0)
        count = end - start
        phases = (phase + np.arange(count) * hz / output_rate) % 1.0
        output[start:end] = np.where(phases < 0.5, 9000, -9000).astype(np.int16)
        phase = float((phase + count * hz / output_rate) % 1.0)
    return output


def write_wav(path: Path, samples: np.ndarray, sample_rate: int = OUTPUT_RATE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(samples.astype("<i2", copy=False).tobytes())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    pcm = decode_audio(args.video)
    times, notes, confidence = extract_pitch_track(pcm, ANALYSIS_RATE)
    duration = len(pcm) / ANALYSIS_RATE
    preview = synthesize_square(notes, duration)
    write_wav(args.output, preview)
    voiced = notes >= 0
    changes = int(np.count_nonzero(notes[1:] != notes[:-1])) if len(notes) > 1 else 0
    report = {
        "source": str(args.video),
        "duration_seconds": duration,
        "analysis_rate": ANALYSIS_RATE,
        "analysis_hop_ms": HOP_SIZE * 1000 / ANALYSIS_RATE,
        "voiced_ratio": float(np.mean(voiced)),
        "median_confidence": float(np.median(confidence[voiced])) if np.any(voiced) else 0.0,
        "note_min": int(np.min(notes[voiced])) if np.any(voiced) else None,
        "note_max": int(np.max(notes[voiced])) if np.any(voiced) else None,
        "pitch_changes": changes,
        "output": str(args.output),
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                               encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
