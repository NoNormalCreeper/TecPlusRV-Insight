#!/usr/bin/env python3
"""真实 Bad Apple 本地素材转换的最小回归。"""

from __future__ import annotations

import tempfile
import unittest
import struct
from pathlib import Path

import make_bad_apple_minimal_asset as packer


REPO_ROOT = Path(__file__).resolve().parent.parent
VIDEO = REPO_ROOT / "firmware/assets/bad-apple.mp4"
MIDI = REPO_ROOT / "firmware/assets/badapple-midifull.mid"


class RealAssetTest(unittest.TestCase):
    @staticmethod
    def write_midi(path: Path, track_data: bytes) -> None:
        path.write_bytes(
            b"MThd" + struct.pack(">IHHH", 6, 1, 1, 96) +
            b"MTrk" + struct.pack(">I", len(track_data)) + track_data
        )

    def test_midi_running_status_and_system_event_clear(self) -> None:
        valid_track = bytes.fromhex(
            "00 ff 03 04 54 65 73 74 "
            "00 90 3c 40 10 3e 40 10 3c 00 00 90 3e 00 00 ff 2f 00"
        )
        invalid_track = bytes.fromhex(
            "00 90 3c 40 00 ff 01 01 78 00 3e 40 00 ff 2f 00"
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            valid = Path(temp_dir) / "valid.mid"
            invalid = Path(temp_dir) / "invalid.mid"
            self.write_midi(valid, valid_track)
            self.write_midi(invalid, invalid_track)
            parsed = packer.parse_midi(valid)
            self.assertEqual(len(parsed["tracks"][0]["events"]), 4)
            with self.assertRaisesRegex(ValueError, "running status"):
                packer.parse_midi(invalid)

    def test_real_video_extracts_twenty_seconds(self) -> None:
        frames = packer.extract_binary_frames(VIDEO, start_seconds=30.0, duration_seconds=20.0)
        self.assertGreaterEqual(len(frames), 297)
        self.assertLessEqual(len(frames), 299)
        self.assertTrue(all(len(frame) == 1200 for frame in frames))
        self.assertGreater(len(set(frames)), 100)

    def test_real_midi_selects_synth1_and_clips_events(self) -> None:
        midi = packer.parse_midi(MIDI)
        self.assertEqual(midi["format"], 1)
        self.assertEqual(midi["ppqn"], 96)
        self.assertEqual(len(midi["tracks"]), 13)
        events = packer.build_midi_frame_events(
            midi,
            track_name="Synth1, Midi name: Bad apple!!",
            clip_start_seconds=30.0,
            clip_duration_seconds=20.0,
            transpose=-12,
        )
        self.assertGreater(len(events), 20)
        self.assertTrue(all(0 <= frame < 299 for frame, _hz in events))
        self.assertTrue(any(hz > 0 for _frame, hz in events))

    def test_preview_is_a_gif(self) -> None:
        frames = packer.extract_binary_frames(VIDEO, start_seconds=30.0, duration_seconds=1.0)
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "preview.gif"
            packer.write_preview_gif(frames, output)
            self.assertTrue(output.read_bytes().startswith(b"GIF8"))

    def test_real_asset_obeys_player_limits(self) -> None:
        data, frames, notes = packer.build_real_asset(
            VIDEO,
            MIDI,
            start_seconds=30.0,
            duration_seconds=1.0,
            track_name="Synth1, Midi name: Bad apple!!",
            transpose=-12,
        )
        packer.validate_player_asset(data)
        self.assertEqual(struct.unpack_from("<I", data, 12)[0], len(frames))
        self.assertEqual(struct.unpack_from("<I", data, 24)[0], len(notes))
        invalid = bytearray(data)
        struct.pack_into("<I", invalid, 12, 1001)
        with self.assertRaisesRegex(ValueError, "frame_count"):
            packer.validate_player_asset(bytes(invalid))


if __name__ == "__main__":
    unittest.main()
