import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np


SHELL = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("sound_trigger", SHELL / "scripts/sound_trigger.py")
st = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(st)


def _synth_bell(duration=0.45, amp=0.35):
    t = np.arange(int(round(duration * st.SAMPLE_RATE)), dtype=np.float32) / st.SAMPLE_RATE
    attack = np.minimum(1.0, t / 0.006)
    ring = (
        1.00 * np.sin(2.0 * np.pi * 1480.0 * t) * np.exp(-t * 5.5)
        + 0.62 * np.sin(2.0 * np.pi * 2995.0 * t) * np.exp(-t * 8.0)
        + 0.38 * np.sin(2.0 * np.pi * 4420.0 * t) * np.exp(-t * 11.5)
    )
    out = amp * attack * ring / 1.45
    return out.astype(np.float32)


def _synth_noisy_bed(seconds, rng, level=0.10):
    n = int(round(seconds * st.SAMPLE_RATE))
    t = np.arange(n, dtype=np.float32) / st.SAMPLE_RATE
    white = rng.standard_normal(n).astype(np.float32)
    spec = np.fft.rfft(white)
    freqs = np.fft.rfftfreq(n, d=1.0 / st.SAMPLE_RATE)
    pink_shape = 1.0 / np.sqrt(np.maximum(freqs, 40.0))
    pink = np.fft.irfft(spec * pink_shape, n=n).astype(np.float32)
    pink /= float(np.sqrt(np.mean(pink * pink)) + 1e-8)
    hum = 0.35 * np.sin(2.0 * np.pi * 120.0 * t) + 0.20 * np.sin(2.0 * np.pi * 240.0 * t)
    bed = level * (0.85 * pink + 0.35 * hum)
    return bed.astype(np.float32)


class SoundTriggerDspTest(unittest.TestCase):
    def test_inspect_autotrim_snips_bell_and_finds_dominant_pitch(self):
        rng = np.random.default_rng(7)
        clip = _synth_noisy_bed(2.8, rng, level=0.02)
        bell = _synth_bell(duration=0.45, amp=0.45)
        onset = int(1.10 * st.SAMPLE_RATE)
        clip[onset : onset + bell.size] += bell

        with tempfile.TemporaryDirectory(prefix="pangu-snd-") as tmp:
            wav_path = Path(tmp) / "bell_recorded.wav"
            st.write_wav_atomic(wav_path, np.clip(clip * 32767.0, -32768, 32767))
            meta = st.inspect_clip(wav_path, do_autotrim=True)

        self.assertEqual(len(meta["peaks"]), 96)
        self.assertGreaterEqual(meta["trimStart"], 0.95)
        self.assertLessEqual(meta["trimStart"], 1.16)
        self.assertGreaterEqual(meta["trimEnd"], 1.32)
        self.assertLessEqual(meta["trimEnd"], 1.75)
        self.assertTrue(1400 <= meta["dominantHz"] <= 1560, f"unexpected dominantHz: {meta['dominantHz']}")
        self.assertLess(meta["bandMinHz"], 1480)
        self.assertGreater(meta["bandMaxHz"], 2900)

    def test_sample_template_matches_bell_in_heavy_noise_and_rejects_distractors(self):
        rng = np.random.default_rng(42)
        clean_bell = _synth_bell(duration=0.45, amp=0.40)
        padded_ref = np.zeros(int(1.2 * st.SAMPLE_RATE), dtype=np.float32)
        padded_ref[int(0.30 * st.SAMPLE_RATE) : int(0.30 * st.SAMPLE_RATE) + clean_bell.size] = clean_bell
        t0, t1 = st.auto_trim_bounds(padded_ref)

        untouched_rule = st.SampleTemplate("bell_snip", padded_ref, trim_start=t0, trim_end=t1, threshold=0.70, cooldown_ms=900)
        tight_rule = st.SampleTemplate("bell_tight", clean_bell, trim_start=0.0, trim_end=0.45, threshold=0.70, cooldown_ms=900)
        telemetry_rule = st.SampleTemplate("bell_tel", clean_bell, threshold=0.70, cooldown_ms=900, telemetry_only=True)
        rules = [untouched_rule, tight_rule, telemetry_rule]

        stream = _synth_noisy_bed(6.2, rng, level=0.14)
        t_speech = np.arange(int(0.50 * st.SAMPLE_RATE), dtype=np.float32) / st.SAMPLE_RATE
        speech = 0.28 * (
            np.sin(2.0 * np.pi * 210.0 * t_speech)
            + 0.8 * np.sin(2.0 * np.pi * 420.0 * t_speech)
            + 0.5 * np.sin(2.0 * np.pi * 630.0 * t_speech)
            + 0.3 * np.sin(2.0 * np.pi * 840.0 * t_speech)
        ) * np.hanning(t_speech.size)
        stream[int(0.9 * st.SAMPLE_RATE) : int(0.9 * st.SAMPLE_RATE) + speech.size] += speech.astype(np.float32)

        crash_len = int(0.22 * st.SAMPLE_RATE)
        crash_env = np.exp(-np.linspace(0.0, 6.0, crash_len, dtype=np.float32))
        crash = 0.48 * rng.standard_normal(crash_len).astype(np.float32) * crash_env
        stream[int(1.85 * st.SAMPLE_RATE) : int(1.85 * st.SAMPLE_RATE) + crash_len] += crash

        analyzer = st.StreamAnalyzer()
        distractor_end = int(2.55 * st.SAMPLE_RATE)
        d_scores, d_matches = analyzer.feed_samples(stream[:distractor_end], rules, [])
        self.assertEqual(d_matches, [], f"unexpected false match on distractors: {d_scores}")
        self.assertLess(d_scores["bell_snip"], 0.65)
        self.assertLess(d_scores["bell_tight"], 0.65)

        bell_noisy = _synth_bell(duration=0.45, amp=0.28)
        b1 = int(2.90 * st.SAMPLE_RATE)
        b_echo = int(3.35 * st.SAMPLE_RATE)
        b2 = int(4.55 * st.SAMPLE_RATE)
        stream[b1 : b1 + bell_noisy.size] += bell_noisy
        stream[b_echo : b_echo + bell_noisy.size] += 0.85 * bell_noisy
        stream[b2 : b2 + bell_noisy.size] += bell_noisy

        t_scores, t_matches = analyzer.feed_samples(stream[distractor_end:], rules, [])
        fired_snip = [m for m in t_matches if m[0] == "bell_snip"]
        fired_tight = [m for m in t_matches if m[0] == "bell_tight"]
        fired_tel = [m for m in t_matches if m[0] == "bell_tel"]

        self.assertEqual(len(fired_snip), 2, f"expected 2 matches respecting cooldown, got {fired_snip} (scores={t_scores})")
        self.assertEqual(len(fired_tight), 2, f"expected 2 matches for tight bell, got {fired_tight} (scores={t_scores})")
        self.assertEqual(fired_tel, [])
        self.assertGreaterEqual(t_scores["bell_tel"], 0.70)

    def test_sample_template_matches_arbitrary_two_pulse_sound_in_noise(self):
        rng = np.random.default_rng(123)
        n_pulse = int(0.08 * st.SAMPLE_RATE)
        t_p = np.arange(n_pulse, dtype=np.float32) / st.SAMPLE_RATE
        chirp1 = 0.42 * np.sin(2.0 * np.pi * (700.0 * t_p + 4500.0 * t_p * t_p)) * np.hanning(n_pulse)
        chirp2 = 0.45 * np.sin(2.0 * np.pi * (1100.0 * t_p + 6000.0 * t_p * t_p)) * np.hanning(n_pulse)
        motif = np.zeros(int(0.24 * st.SAMPLE_RATE), dtype=np.float32)
        motif[:n_pulse] = chirp1
        motif[int(0.13 * st.SAMPLE_RATE) : int(0.13 * st.SAMPLE_RATE) + n_pulse] = chirp2

        rule = st.SampleTemplate("queue_pop", motif, threshold=0.70, cooldown_ms=800)
        analyzer = st.StreamAnalyzer()
        stream = _synth_noisy_bed(3.2, rng, level=0.11)
        stream[int(0.7 * st.SAMPLE_RATE) : int(0.7 * st.SAMPLE_RATE) + n_pulse] += chirp1
        pre = int(1.4 * st.SAMPLE_RATE)
        _, pre_matches = analyzer.feed_samples(stream[:pre], [rule], [])
        self.assertEqual(pre_matches, [])

        stream[int(1.9 * st.SAMPLE_RATE) : int(1.9 * st.SAMPLE_RATE) + motif.size] += 0.85 * motif
        post_scores, post_matches = analyzer.feed_samples(stream[pre:], [rule], [])
        self.assertEqual(len(post_matches), 1, f"expected 1 motif match, got {post_matches} ({post_scores})")

    def test_frequency_rule_detects_tonal_bell_and_ignores_broadband_or_low_tones(self):
        rng = np.random.default_rng(99)
        freq_rule = st.FrequencyRule("chime_band", min_hz=1250, max_hz=3400, min_duration_ms=65, threshold=0.70, cooldown_ms=1000)
        analyzer = st.StreamAnalyzer()

        stream = _synth_noisy_bed(3.6, rng, level=0.08)
        t_low = np.arange(int(0.30 * st.SAMPLE_RATE), dtype=np.float32) / st.SAMPLE_RATE
        stream[int(0.6 * st.SAMPLE_RATE) : int(0.6 * st.SAMPLE_RATE) + t_low.size] += (
            0.35 * np.sin(2.0 * np.pi * 320.0 * t_low)
        ).astype(np.float32)
        burst_len = int(0.20 * st.SAMPLE_RATE)
        stream[int(1.3 * st.SAMPLE_RATE) : int(1.3 * st.SAMPLE_RATE) + burst_len] += (
            0.42 * rng.standard_normal(burst_len)
        ).astype(np.float32)

        pre_end = int(1.95 * st.SAMPLE_RATE)
        pre_scores, pre_matches = analyzer.feed_samples(stream[:pre_end], [], [freq_rule])
        self.assertEqual(pre_matches, [], f"false frequency trigger: {pre_scores}")

        bell = _synth_bell(duration=0.40, amp=0.30)
        b_idx = int(2.25 * st.SAMPLE_RATE)
        stream[b_idx : b_idx + bell.size] += bell
        post_scores, post_matches = analyzer.feed_samples(stream[pre_end:], [], [freq_rule])
        self.assertEqual(len(post_matches), 1, f"expected 1 frequency match, got {post_matches} (scores={post_scores})")
        self.assertGreaterEqual(post_scores["chime_band"], 0.70)

    def test_compile_rules_splits_desktop_mic_and_both(self):
        with tempfile.TemporaryDirectory(prefix="pangu-snd-cfg-") as tmp:
            root = Path(tmp)
            wav = root / "sample.wav"
            st.write_wav_atomic(wav, (_synth_bell() * 32767.0).astype(np.int16))
            cfg = root / "rules.json"
            cfg.write_text(
                json.dumps(
                    {
                        "telemetry": True,
                        "rules": [
                            {"id": "m1", "mode": "sample", "source": "both", "samplePath": str(wav), "threshold": 72},
                            {"id": "m2", "mode": "frequency", "source": "mic", "minHz": 1200, "maxHz": 3200, "threshold": 68},
                        ],
                    }
                )
            )
            by_source, telemetry = st._compile_rules(cfg)
            self.assertTrue(telemetry)
            self.assertEqual([r.id for r in by_source["desktop"][0]], ["m1"])
            self.assertEqual([r.id for r in by_source["desktop"][1]], [])
            self.assertEqual([r.id for r in by_source["mic"][0]], ["m1"])
            self.assertEqual([r.id for r in by_source["mic"][1]], ["m2"])


if __name__ == "__main__":
    unittest.main()
