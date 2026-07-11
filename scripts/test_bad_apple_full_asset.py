#!/usr/bin/env python3
"""完整版 Bad Apple BAM2 packer 回归。"""

import importlib.util
import io
import tempfile
import unittest
import wave
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PACKER_PATH = REPO_ROOT / "scripts/make_bad_apple_full_asset.py"


def load_packer():
    spec = importlib.util.spec_from_file_location("bad_apple_full_packer", PACKER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MidiReducerTest(unittest.TestCase):
    def setUp(self):
        self.packer = load_packer()

    @staticmethod
    def midi(tracks):
        return {"ppqn": 100, "tempos": [(0, 1_000_000)], "tracks": tracks}

    def test_single_track_sections_are_not_dropped(self):
        midi = self.midi([
            {"name": "Vocals", "events": [(100, 0, True, 72), (200, 1, False, 72)]},
            {"name": "Synth2", "events": [(0, 0, True, 40), (100, 1, False, 40)]},
        ])
        events = self.packer.build_all_track_events(
            midi, duration_seconds=2.1, offset_seconds=0.0, time_scale=1.0,
            transpose=-12,
        )
        self.assertEqual(events, [(0, self.packer.note_hz(52)),
                                  (60, self.packer.note_hz(60)), (119, 0)])

    def test_note_release_restores_still_active_track(self):
        midi = self.midi([
            {"name": "Vocals", "events": [(50, 0, True, 72), (100, 1, False, 72)]},
            {"name": "Synth2", "events": [(0, 0, True, 60), (150, 1, False, 60)]},
        ])
        events = self.packer.build_all_track_events(
            midi, duration_seconds=2.0, offset_seconds=0.0, time_scale=1.0,
            transpose=0,
        )
        self.assertEqual(events, [(0, self.packer.note_hz(84)),
                                  (30, self.packer.note_hz(72)),
                                  (60, self.packer.note_hz(84)), (89, 0)])

    def test_same_tick_off_then_on_does_not_emit_false_silence(self):
        midi = self.midi([
            {"name": "Vocals", "events": [
                (0, 0, True, 72), (100, 1, False, 72), (100, 2, True, 74),
                (200, 3, False, 74),
            ]},
        ])
        events = self.packer.build_all_track_events(
            midi, duration_seconds=2.1, offset_seconds=0.0, time_scale=1.0,
            transpose=0,
        )
        self.assertEqual(events, [(0, self.packer.note_hz(72)),
                                  (60, self.packer.note_hz(74)), (119, 0)])

    def test_clip_restores_frequency_active_at_start(self):
        events = [(10, 440), (80, 494), (130, 0)]
        self.assertEqual(self.packer.clip_audio_events(events, 60, 120),
                         [(0, 440), (20, 494)])

    def test_default_offset_matches_mp4_leading_silence(self):
        self.assertAlmostEqual(self.packer.MIDI_OFFSET_SECONDS, 1.369, places=6)

    def test_synth2_intro_melody_beats_bass_tracks(self):
        midi = self.midi([
            {"name": "Synth2", "events": [(0, 0, True, 72)]},
            {"name": "Bass2", "events": [(0, 0, True, 40)]},
        ])
        events = self.packer.build_all_track_events(
            midi, duration_seconds=1.0, offset_seconds=0.0, time_scale=1.0,
            transpose=0,
        )
        self.assertEqual(events, [(0, self.packer.note_hz(96))])

    def test_percussion_and_bass_are_not_rendered_as_pitch(self):
        midi = self.midi([
            {"name": "Drums", "events": [(0, 0, True, 36)]},
            {"name": "Sub bass", "events": [(0, 0, True, 40)]},
            {"name": "Perc1", "events": [(0, 0, True, 60)]},
        ])
        self.assertEqual(self.packer.build_all_track_events(
            midi, duration_seconds=1.0, offset_seconds=0.0, time_scale=1.0,
            transpose=0,
        ), [])

    def test_synth1_takes_lead_when_it_enters(self):
        midi = self.midi([
            {"name": "Vocals", "events": [(0, 0, True, 72)]},
            {"name": "Synth1", "events": [(100, 0, True, 76)]},
        ])
        events = self.packer.build_all_track_events(
            midi, duration_seconds=2.0, offset_seconds=0.0, time_scale=1.0,
            transpose=0,
        )
        self.assertEqual(events, [(0, self.packer.note_hz(72)),
                                  (60, self.packer.note_hz(76))])

    def test_compact_piano_turns_low_chords_into_clicks(self):
        midi = self.midi([
            {"name": "", "events": []},
            {"name": "", "events": []},
            {"name": "", "events": [
                (0, 0, True, 22), (0, 1, True, 27),
                (10, 2, False, 22), (10, 3, False, 27),
                (100, 4, True, 22), (100, 5, True, 27),
                (100, 6, True, 34), (100, 7, True, 39),
            ]},
        ])
        events = self.packer.build_compact_piano_events(
            midi, duration_seconds=2.0, offset_seconds=0.0, time_scale=1.0,
            transpose=-12,
        )
        self.assertEqual(events, [(0, 180), (1, 110), (2, 70), (3, 0),
                                  (60, 360), (61, 220), (62, 120), (63, 0)])

    def test_compact_piano_uses_lower_octave_melody_note(self):
        midi = self.midi([
            {"name": "", "events": []},
            {"name": "", "events": []},
            {"name": "", "events": [
                (0, 0, True, 89), (0, 1, True, 77),
                (100, 2, False, 89), (100, 3, False, 77),
            ]},
        ])
        events = self.packer.build_compact_piano_events(
            midi, duration_seconds=2.0, offset_seconds=0.0, time_scale=1.0,
            transpose=-12,
        )
        self.assertEqual(events, [(0, self.packer.note_hz(65)), (60, 0)])

    def test_compact_piano_uses_second_track_only_when_melody_is_idle(self):
        midi = self.midi([
            {"name": "", "events": []},
            {"name": "", "events": []},
            {"name": "", "events": [
                (0, 0, True, 72), (100, 1, False, 72),
            ]},
            {"name": "", "events": [
                (50, 0, True, 40), (150, 1, True, 42),
            ]},
        ])
        events = self.packer.build_compact_piano_events(
            midi, duration_seconds=2.0, offset_seconds=0.0, time_scale=1.0,
            transpose=0,
        )
        self.assertEqual(events, [(0, self.packer.note_hz(72)), (60, 0),
                                  (89, 240), (90, 140), (91, 80), (92, 0)])

    def test_compact_piano_keeps_phrase_gaps_clean(self):
        midi = self.midi([
            {"name": "", "events": []},
            {"name": "", "events": []},
            {"name": "", "events": [
                (0, 0, True, 72), (50, 1, False, 72),
                (200, 2, True, 74), (250, 3, False, 74),
            ]},
            {"name": "", "events": [(100, 0, True, 40)]},
        ])
        events = self.packer.build_compact_piano_events(
            midi, duration_seconds=3.0, offset_seconds=0.0, time_scale=1.0,
            transpose=0,
        )
        self.assertEqual(events, [(0, self.packer.note_hz(72)), (30, 0),
                                  (119, self.packer.note_hz(74)), (149, 0)])

    def test_compact_piano_fills_only_long_interlude(self):
        midi = self.midi([
            {"name": "", "events": []},
            {"name": "", "events": []},
            {"name": "", "events": [
                (0, 0, True, 72), (50, 1, False, 72),
                (500, 2, True, 74), (550, 3, False, 74),
            ]},
            {"name": "", "events": [
                (100, 0, True, 40), (150, 1, False, 40),
                (200, 2, True, 46), (200, 3, True, 51),
            ]},
        ])
        events = self.packer.build_compact_piano_events(
            midi, duration_seconds=6.0, offset_seconds=0.0, time_scale=1.0,
            transpose=0,
        )
        self.assertEqual(events, [(0, self.packer.note_hz(72)), (30, 0),
                                  (60, self.packer.note_hz(64)),
                                  (119, self.packer.note_hz(75)),
                                  (298, self.packer.note_hz(74)), (327, 0)])

    def test_compact_interlude_folds_low_notes_into_buzzer_range(self):
        self.assertEqual(self.packer.fold_note_to_range(39, 52, 76), 63)


class Bam2Test(unittest.TestCase):
    def setUp(self):
        self.packer = load_packer()

    def test_round_trip_replacement_diff_and_audio(self):
        frames = [[0] * 96, [0] * 95 + [0x80000000], [1] + [0] * 94 + [0x80000000]]
        audio = [(0, 440), (6, 0)]
        data = self.packer.encode_asset(frames, audio, duration_ticks=12)
        report = self.packer.validate_asset(data)
        self.assertEqual(report["frame_count"], 3)
        self.assertEqual(report["audio_event_count"], 2)
        self.assertEqual(report["duration_vga_ticks"], 12)
        self.assertEqual(report["decoded_frames"], frames)
        self.assertEqual(report["decoded_audio_events"], audio)

    def test_asset_limit_is_enforced(self):
        self.packer.MAX_ASSET_BYTES = 64
        with self.assertRaisesRegex(ValueError, "16 MiB|上限"):
            self.packer.encode_asset([[0] * 96], [], duration_ticks=1)

    def test_real_video_and_official_compact_midi_one_second(self):
        video = REPO_ROOT / "firmware/assets/bad-apple.mp4"
        midi_path = REPO_ROOT / "firmware/assets/touhou-bad-apple-featnomico-26035-nonstop2k.com.mid"
        frames = self.packer.extract_bitmap_frames(
            video, start_seconds=30.0, duration_seconds=1.0)
        midi = self.packer.parse_midi(midi_path)
        offset = 217.080 - midi["duration_seconds"]
        all_events = self.packer.build_compact_piano_events(
            midi, duration_seconds=31.0, offset_seconds=offset,
            time_scale=1.0, transpose=-12)
        start_tick = round(30.0 * self.packer.VGA_TICKS_NUM /
                           self.packer.VGA_TICKS_DEN)
        events = self.packer.clip_audio_events(all_events, start_tick,
                                               start_tick + 60)
        data = self.packer.encode_asset(frames, events, duration_ticks=60)
        report = self.packer.validate_asset(data)
        self.assertEqual(report["frame_count"], 10)
        self.assertGreater(report["audio_event_count"], 0)
        self.assertEqual(sum(bool(track["events"]) for track in midi["tracks"]), 2)

    def test_preview_wav_matches_asset_duration(self):
        data = self.packer.build_synthetic_asset()
        output = io.BytesIO()
        self.packer.write_buzzer_wav(data, output, sample_rate=8000)
        output.seek(0)
        with wave.open(output, "rb") as wav:
            self.assertEqual(wav.getnchannels(), 1)
            self.assertEqual(wav.getsampwidth(), 2)
            self.assertEqual(wav.getframerate(), 8000)
            self.assertEqual(wav.getnframes(), round(72 * 21 / 1250 * 8000))

    def test_preview_wav_accepts_path(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "preview.wav"
            self.packer.write_buzzer_wav(
                self.packer.build_synthetic_asset(), output, sample_rate=8000)
            self.assertGreater(output.stat().st_size, 44)


if __name__ == "__main__":
    unittest.main()
