#!/usr/bin/env python3
"""原视频音轨单音提取预览测试。"""

import importlib.util
import unittest
from pathlib import Path

import numpy as np


SCRIPT = Path(__file__).with_name("make_bad_apple_source_audio.py")


def load_module():
    spec = importlib.util.spec_from_file_location("source_audio", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PitchTest(unittest.TestCase):
    def setUp(self):
        self.module = load_module()

    def test_detects_440_hz_sine(self):
        sample_rate = 8000
        time = np.arange(sample_rate * 2) / sample_rate
        samples = (0.4 * np.sin(2 * np.pi * 440 * time)).astype(np.float32)
        times, notes, confidence = self.module.extract_pitch_track(samples, sample_rate)
        voiced = notes[confidence > 0.1]
        self.assertGreater(len(voiced), 20)
        self.assertAlmostEqual(float(np.median(voiced)), 69, delta=1)

    def test_silence_stays_silent(self):
        samples = np.zeros(16000, dtype=np.float32)
        _times, notes, _confidence = self.module.extract_pitch_track(samples, 8000)
        self.assertTrue(np.all(notes == -1))


if __name__ == "__main__":
    unittest.main()
