#!/usr/bin/env python3
import argparse
import json
import math
import os
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 16000
WIN_SIZE = 512
HOP_SIZE = 256
N_BINS = WIN_SIZE // 2 + 1
N_BANDS = 40
MIN_CLIP_SEC = 0.06
MAX_CLIP_SEC = 8.0

_HANN = np.hanning(WIN_SIZE).astype(np.float32)
_BIN_HZ = np.linspace(0.0, SAMPLE_RATE / 2.0, N_BINS, dtype=np.float32)


def _build_filterbank():
    edges = np.geomspace(80.0, 7600.0, N_BANDS + 2).astype(np.float32)
    centers = edges[1:-1]
    fb = np.zeros((N_BANDS, N_BINS), dtype=np.float32)
    for idx in range(N_BANDS):
        lo, mid, hi = edges[idx], edges[idx + 1], edges[idx + 2]
        up = (_BIN_HZ - lo) / max(mid - lo, 1e-5)
        down = (hi - _BIN_HZ) / max(hi - mid, 1e-5)
        row = np.maximum(0.0, np.minimum(up, down))
        total = float(row.sum())
        if total > 0:
            row /= total
        fb[idx] = row
    kernel_idx = np.arange(-7, 8, dtype=np.float32)
    smooth = np.exp(-0.5 * (kernel_idx / 3.0) ** 2)
    smooth /= smooth.sum()
    return fb, centers, smooth.astype(np.float32)


_FILTERBANK, BAND_CENTERS_HZ, _BAND_SMOOTH = _build_filterbank()


def _smooth_bands(matrix):
    padded = np.pad(matrix, ((0, 0), (7, 7)), mode="edge")
    out = np.empty_like(matrix)
    for idx in range(matrix.shape[1]):
        out[:, idx] = (padded[:, idx : idx + 15] * _BAND_SMOOTH).sum(axis=1)
    return out


def read_wav_mono(path):
    with wave.open(str(path), "rb") as wf:
        channels = wf.getnchannels()
        width = wf.getsampwidth()
        rate = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    if width == 2:
        pcm = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    elif width == 4:
        pcm = np.frombuffer(raw, dtype=np.int32).astype(np.float32) / 2147483648.0
    elif width == 1:
        pcm = (np.frombuffer(raw, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    else:
        raise ValueError(f"Unsupported WAV sample width: {width}")
    if channels > 1:
        pcm = pcm.reshape(-1, channels).mean(axis=1)
    if rate != SAMPLE_RATE and pcm.size > 0:
        duration = pcm.size / float(rate)
        target_len = max(1, int(round(duration * SAMPLE_RATE)))
        src_x = np.linspace(0.0, 1.0, pcm.size, endpoint=False)
        dst_x = np.linspace(0.0, 1.0, target_len, endpoint=False)
        pcm = np.interp(dst_x, src_x, pcm).astype(np.float32)
    return pcm


def write_wav_atomic(path, samples_int16):
    dest = Path(path)
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".snd-", suffix=".wav", dir=str(dest.parent))
    os.close(fd)
    try:
        with wave.open(tmp_name, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(samples_int16.astype(np.int16).tobytes())
        os.replace(tmp_name, str(dest))
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def frame_audio(samples):
    if samples.size < WIN_SIZE:
        padded = np.zeros(WIN_SIZE, dtype=np.float32)
        padded[: samples.size] = samples
        return padded[None, :]
    count = 1 + (samples.size - WIN_SIZE) // HOP_SIZE
    strides = (samples.strides[0] * HOP_SIZE, samples.strides[0])
    return np.lib.stride_tricks.as_strided(samples, shape=(count, WIN_SIZE), strides=strides).copy()


def stft_power(samples):
    frames = frame_audio(np.asarray(samples, dtype=np.float32))
    spec = np.fft.rfft(frames * _HANN[None, :], axis=1)
    power = (spec.real ** 2 + spec.imag ** 2).astype(np.float32) / float(WIN_SIZE)
    bands = power @ _FILTERBANK.T
    return power, bands


def auto_trim_bounds(samples):
    duration = samples.size / float(SAMPLE_RATE)
    if duration <= MIN_CLIP_SEC * 2:
        return 0.0, round(duration, 3)
    _, bands = stft_power(samples)
    floor = np.percentile(bands, 55, axis=0) * 1.35 + 1e-7
    fg = np.log1p(np.maximum(0.0, bands - floor) / floor)
    flux = np.maximum(0.0, np.diff(fg, axis=0, prepend=fg[0:1]))
    k = min(4, N_BANDS)
    top_fg = np.partition(fg, N_BANDS - k, axis=1)[:, -k:].mean(axis=1)
    top_flux = np.partition(flux, N_BANDS - k, axis=1)[:, -k:].mean(axis=1)
    raw_act = top_fg + 1.2 * top_flux
    activity = np.convolve(raw_act, np.array([0.25, 0.5, 0.25], dtype=np.float32), mode="same")
    peak = float(activity.max())
    if peak <= 1e-4:
        return 0.0, round(min(duration, MAX_CLIP_SEC), 3)
    baseline = float(np.percentile(activity, 35))
    cutoff = baseline + 0.22 * (peak - baseline)
    active = np.flatnonzero(activity >= cutoff)
    if active.size == 0:
        return 0.0, round(min(duration, MAX_CLIP_SEC), 3)
    peak_idx = int(np.argmax(activity))
    # Keep the contiguous sound event around the strongest transient/chime.
    gap_limit = max(2, int(0.18 * SAMPLE_RATE / HOP_SIZE))
    clusters = []
    start = int(active[0])
    prev = start
    for idx in active[1:]:
        idx = int(idx)
        if idx - prev > gap_limit:
            clusters.append((start, prev))
            start = idx
        prev = idx
    clusters.append((start, prev))
    chosen = clusters[0]
    for lo, hi in clusters:
        if lo <= peak_idx <= hi:
            chosen = (lo, hi)
            break
    t0 = max(0.0, chosen[0] * HOP_SIZE / SAMPLE_RATE - 0.03)
    t1 = min(duration, (chosen[1] * HOP_SIZE + WIN_SIZE) / SAMPLE_RATE + 0.06)
    if t1 - t0 < MIN_CLIP_SEC:
        mid = 0.5 * (t0 + t1)
        t0 = max(0.0, mid - MIN_CLIP_SEC * 0.5)
        t1 = min(duration, t0 + MIN_CLIP_SEC)
    if t1 - t0 > MAX_CLIP_SEC:
        t1 = t0 + MAX_CLIP_SEC
    return round(t0, 3), round(t1, 3)


def inspect_clip(path, trim_start=None, trim_end=None, peaks_count=96, do_autotrim=False):
    samples = read_wav_mono(path)
    duration = samples.size / float(SAMPLE_RATE)
    if do_autotrim or trim_start is None or trim_end is None or trim_end <= trim_start:
        t0, t1 = auto_trim_bounds(samples)
        if not do_autotrim and trim_start is not None and trim_end is not None and trim_end > trim_start:
            t0, t1 = trim_start, trim_end
    else:
        t0 = max(0.0, min(float(trim_start), max(0.0, duration - MIN_CLIP_SEC)))
        t1 = max(t0 + MIN_CLIP_SEC, min(float(trim_end), duration))
    peaks = []
    if samples.size > 0 and peaks_count > 0:
        edges = np.linspace(0, samples.size, peaks_count + 1, dtype=int)
        raw_peaks = [
            float(np.max(np.abs(samples[edges[i] : max(edges[i] + 1, edges[i + 1])])))
            for i in range(peaks_count)
        ]
        scale = max(max(raw_peaks, default=0.0), 1e-4)
        peaks = [round(min(1.0, p / scale), 3) for p in raw_peaks]
    s0 = max(0, min(samples.size, int(round(t0 * SAMPLE_RATE))))
    s1 = max(s0 + 1, min(samples.size, int(round(t1 * SAMPLE_RATE))))
    snip = samples[s0:s1]
    power, bands = stft_power(snip if snip.size > 0 else np.zeros(WIN_SIZE, dtype=np.float32))
    valid_bins = (_BIN_HZ >= 80.0) & (_BIN_HZ <= 7600.0)
    mean_bins = power[:, valid_bins].mean(axis=0)
    valid_hz = _BIN_HZ[valid_bins]
    dom_hz = int(round(float(valid_hz[int(np.argmax(mean_bins))]))) if mean_bins.size else 1000
    band_fg = np.log1p(bands / (float(bands.max()) * 0.01 + 1e-7)).mean(axis=0)
    band_peak = float(band_fg.max())
    salient = np.flatnonzero(band_fg >= 0.28 * band_peak) if band_peak > 0 else np.array([10, 25])
    lo_hz = int(round(max(80.0, float(BAND_CENTERS_HZ[int(salient[0])]) * 0.8)))
    hi_hz = int(round(min(7800.0, float(BAND_CENTERS_HZ[int(salient[-1])]) * 1.25)))
    if hi_hz <= lo_hz + 80:
        lo_hz = max(80, dom_hz - 250)
        hi_hz = min(7800, dom_hz + 250)
    return {
        "duration": round(duration, 3),
        "trimStart": round(t0, 3),
        "trimEnd": round(t1, 3),
        "peaks": peaks,
        "dominantHz": dom_hz,
        "bandMinHz": lo_hz,
        "bandMaxHz": hi_hz,
    }


class SampleTemplate:
    def __init__(self, rule_id, samples, trim_start=0.0, trim_end=0.0, band_filter=False, min_hz=80.0, max_hz=7600.0, threshold=0.70, cooldown_ms=1500, telemetry_only=False):
        self.id = rule_id
        self.threshold = float(np.clip(threshold, 0.30, 0.98))
        self.cooldown_hops = max(1, int(round(cooldown_ms / (1000.0 * HOP_SIZE / SAMPLE_RATE))))
        self.telemetry_only = bool(telemetry_only)
        duration = samples.size / float(SAMPLE_RATE)
        t0 = max(0.0, float(trim_start or 0.0))
        t1 = float(trim_end) if trim_end and trim_end > t0 else duration
        t1 = min(duration, min(t0 + MAX_CLIP_SEC, max(t0 + MIN_CLIP_SEC, t1)))
        s0 = max(0, int(round(t0 * SAMPLE_RATE)))
        s1 = max(s0 + WIN_SIZE, min(samples.size, int(round(t1 * SAMPLE_RATE))))
        snip = samples[s0:s1]
        if snip.size < WIN_SIZE:
            padded = np.zeros(WIN_SIZE, dtype=np.float32)
            padded[: snip.size] = snip
            snip = padded
        _, bands = stft_power(snip)
        # Cap reference dynamic range to ~22 dB so studio-clean clips match noisy live streams.
        peak_band = float(bands.max())
        base = np.maximum(0.5 * np.percentile(bands, 15, axis=0), 0.006 * peak_band + 1e-7)
        fg = np.log1p(np.maximum(0.0, bands - base) / base)
        contrast = fg - _smooth_bands(fg)
        flux = np.maximum(0.0, np.diff(fg, axis=0, prepend=fg[0:1] * 0.35))

        mask = np.ones(N_BANDS, dtype=np.float32)
        if band_filter and max_hz > min_hz:
            mask = ((BAND_CENTERS_HZ >= float(min_hz)) & (BAND_CENTERS_HZ <= float(max_hz))).astype(np.float32)
            if mask.sum() == 0:
                mask[:] = 1.0
        fg *= mask[None, :]
        contrast *= mask[None, :]
        flux *= mask[None, :]

        salience = np.sqrt((fg ** 2).mean(axis=0) + 0.5 * (flux ** 2).mean(axis=0))
        sal_max = float(salience.max()) + 1e-8
        weights = np.clip((salience / sal_max) ** 1.15, 0.05, 1.0) * mask
        self.length = fg.shape[0]
        self.band_mask = mask
        self.weights = weights.astype(np.float32)
        self.active_bands = (salience >= 0.22 * sal_max) & (mask > 0)
        if not np.any(self.active_bands):
            self.active_bands = mask > 0

        frame_env = fg[:, self.active_bands].mean(axis=1)
        frame_peak = float(frame_env.max()) + 1e-8
        self.frame_weights = np.clip(frame_env / frame_peak, 0.15, 1.0).astype(np.float32)

        tonality = float(np.std(contrast[:, self.active_bands]) / (np.mean(fg[:, self.active_bands]) + 1e-5))
        self.contrast_mix = float(np.clip(tonality * 1.2, 0.35, 0.78))

        cell_w = np.sqrt(self.frame_weights[:, None] * np.maximum(0.15, weights)[None, :]).astype(np.float32)
        self.cell_w = cell_w
        self.t_contrast = (contrast * cell_w).astype(np.float32)
        self.t_contrast_norm = float(np.linalg.norm(self.t_contrast)) + 1e-8

        act_env = fg[:, self.active_bands].mean(axis=1)
        act_flux = flux[:, self.active_bands].mean(axis=1)
        self.t_env = np.concatenate([act_env / (float(act_env.max()) + 1e-8), 0.75 * act_flux / (float(act_flux.max()) + 1e-8)]).astype(np.float32)
        self.t_env_norm = float(np.linalg.norm(self.t_env)) + 1e-8
        self.min_fg_energy = 0.12

    def score_window(self, fg_win, contrast_win, flux_win):
        act_fg = fg_win[:, self.active_bands]
        active_level = float((act_fg.mean(axis=1) * self.frame_weights).sum() / self.frame_weights.sum())
        if active_level < self.min_fg_energy:
            return 0.0
        live_c = contrast_win * self.band_mask[None, :] * self.cell_w
        c_norm = float(np.linalg.norm(live_c))
        sim_c = float(np.sum(live_c * self.t_contrast) / (c_norm * self.t_contrast_norm)) if c_norm > 1e-6 else 0.0

        act_env = act_fg.mean(axis=1)
        act_flux = flux_win[:, self.active_bands].mean(axis=1)
        env_peak = float(act_env.max())
        flux_peak = float(act_flux.max())
        if env_peak <= 1e-5:
            return 0.0
        live_e = np.concatenate([act_env / env_peak, 0.75 * act_flux / max(flux_peak, 0.15)])
        e_norm = float(np.linalg.norm(live_e))
        sim_e = float(np.sum(live_e * self.t_env) / (e_norm * self.t_env_norm)) if e_norm > 1e-6 else 0.0

        # Penalize broadband bursts whose non-target bands surge as high as target bands.
        inactive = (~self.active_bands) & (self.band_mask > 0)
        broadband_penalty = 1.0
        if np.any(inactive):
            off_level = float((fg_win[:, inactive].mean(axis=1) * self.frame_weights).sum() / self.frame_weights.sum())
            ratio = active_level / (off_level + 0.20)
            if ratio < 1.25:
                broadband_penalty = float(np.clip((ratio - 0.65) / 0.60, 0.25, 1.0))

        raw = (self.contrast_mix * max(0.0, sim_c) + (1.0 - self.contrast_mix) * max(0.0, sim_e)) * broadband_penalty
        energy_gate = min(1.0, active_level / 0.30)
        return float(np.clip(raw * energy_gate, 0.0, 1.0))


class FrequencyRule:
    def __init__(self, rule_id, min_hz=1000.0, max_hz=3600.0, min_duration_ms=60, threshold=0.70, cooldown_ms=1500, telemetry_only=False):
        self.id = rule_id
        lo = max(60.0, min(float(min_hz), 7600.0))
        hi = max(lo + 40.0, min(float(max_hz), 7800.0))
        self.in_bins = (_BIN_HZ >= lo) & (_BIN_HZ <= hi)
        if not np.any(self.in_bins):
            nearest = int(np.argmin(np.abs(_BIN_HZ - 0.5 * (lo + hi))))
            self.in_bins[nearest] = True
        flank_lo = (_BIN_HZ >= max(60.0, lo * 0.45)) & (_BIN_HZ < lo)
        flank_hi = (_BIN_HZ > hi) & (_BIN_HZ <= min(7900.0, hi * 1.85))
        self.flank_bins = flank_lo | flank_hi
        if not np.any(self.flank_bins):
            self.flank_bins = ~self.in_bins
        self.hold_hops = max(1, int(round(float(min_duration_ms) / (1000.0 * HOP_SIZE / SAMPLE_RATE))))
        self.threshold = float(np.clip(threshold, 0.30, 0.98))
        self.cooldown_hops = max(1, int(round(cooldown_ms / (1000.0 * HOP_SIZE / SAMPLE_RATE))))
        self.telemetry_only = bool(telemetry_only)

    def score_frame(self, fg_bins):
        in_vals = fg_bins[self.in_bins]
        k = min(3, in_vals.size)
        top_in = float(np.partition(in_vals, in_vals.size - k)[-k:].mean())
        if top_in < 0.25:
            return 0.0
        flank_vals = fg_bins[self.flank_bins]
        in_med = float(np.median(in_vals))
        flank_p80 = float(np.percentile(flank_vals, 80))
        bg_ref = max(0.75 * in_med, 0.85 * flank_p80)
        # Broadband noise raises both median/flanks and peak; tonal chimes stand cleanly above both.
        prominence = max(0.0, top_in - bg_ref)
        ratio = top_in / (bg_ref + 0.35)
        if ratio < 1.55:
            prominence *= max(0.0, (ratio - 1.0) / 0.55)
        return float(np.clip(1.0 - math.exp(-0.65 * prominence), 0.0, 1.0))


class StreamAnalyzer:
    def __init__(self, max_history_hops=520):
        self.max_hops = max_history_hops
        self.band_floor = None
        self.bin_floor = None
        self.prev_fg = np.zeros(N_BANDS, dtype=np.float32)
        self.fg_hist = np.zeros((max_history_hops, N_BANDS), dtype=np.float32)
        self.contrast_hist = np.zeros((max_history_hops, N_BANDS), dtype=np.float32)
        self.flux_hist = np.zeros((max_history_hops, N_BANDS), dtype=np.float32)
        self.filled = 0
        self.remainder = np.zeros(0, dtype=np.float32)
        self.last_rms = 0.0
        self.last_peak_hz = 0
        self.state = {}

    def _rule_state(self, rule_id):
        st = self.state.get(rule_id)
        if st is None:
            st = {"cooldown": 0, "hold": 0, "armed_peak": 0.0}
            self.state[rule_id] = st
        return st

    def step_frame(self, frame, sample_rules, freq_rules):
        self.last_rms = float(np.sqrt(np.mean(frame * frame)))
        spec = np.fft.rfft(frame * _HANN)
        power_bins = (spec.real ** 2 + spec.imag ** 2).astype(np.float32) / float(WIN_SIZE)
        bands = power_bins @ _FILTERBANK.T

        # Quiet ambient baseline prevents zero-division in digital silence while ignoring hiss.
        min_band_floor = 2e-6
        min_bin_floor = 2e-6
        if self.band_floor is None:
            self.band_floor = np.maximum(bands, min_band_floor)
            self.bin_floor = np.maximum(power_bins, min_bin_floor)
        else:
            up_b = bands > self.band_floor
            self.band_floor = np.where(up_b, 0.988 * self.band_floor + 0.012 * bands, 0.92 * self.band_floor + 0.08 * bands)
            self.band_floor = np.maximum(self.band_floor, min_band_floor)
            up_k = power_bins > self.bin_floor
            self.bin_floor = np.where(up_k, 0.988 * self.bin_floor + 0.012 * power_bins, 0.92 * self.bin_floor + 0.08 * power_bins)
            self.bin_floor = np.maximum(self.bin_floor, min_bin_floor)

        fg = np.log1p(np.maximum(0.0, bands - 0.85 * self.band_floor) / (self.band_floor + min_band_floor))
        contrast = fg - _smooth_bands(fg[None, :])[0]
        flux = np.maximum(0.0, fg - self.prev_fg)
        self.prev_fg = fg

        fg_bins = np.log1p(np.maximum(0.0, power_bins - 0.85 * self.bin_floor) / (self.bin_floor + min_bin_floor))
        valid_bins = (_BIN_HZ >= 80.0) & (_BIN_HZ <= 7600.0)
        vb = fg_bins[valid_bins]
        self.last_peak_hz = int(round(float(_BIN_HZ[valid_bins][int(np.argmax(vb))]))) if vb.size and float(vb.max()) > 0.2 else 0

        if self.filled < self.max_hops:
            idx = self.filled
            self.filled += 1
        else:
            self.fg_hist[:-1] = self.fg_hist[1:]
            self.contrast_hist[:-1] = self.contrast_hist[1:]
            self.flux_hist[:-1] = self.flux_hist[1:]
            idx = self.max_hops - 1
        self.fg_hist[idx] = fg
        self.contrast_hist[idx] = contrast
        self.flux_hist[idx] = flux

        scores = {}
        matches = []

        for rule in sample_rules:
            st = self._rule_state(rule.id)
            if st["cooldown"] > 0:
                st["cooldown"] -= 1
            if self.filled < rule.length:
                scores[rule.id] = 0.0
                continue
            s = self.filled - rule.length
            score = rule.score_window(self.fg_hist[s : self.filled], self.contrast_hist[s : self.filled], self.flux_hist[s : self.filled])
            scores[rule.id] = score
            if st["cooldown"] > 0:
                st["armed_peak"] = 0.0
                continue
            if score >= rule.threshold:
                if score >= st["armed_peak"]:
                    st["armed_peak"] = score
                    if score >= min(0.98, rule.threshold + 0.14):
                        if not rule.telemetry_only:
                            matches.append((rule.id, st["armed_peak"]))
                        st["cooldown"] = rule.cooldown_hops
                        st["armed_peak"] = 0.0
                else:
                    if not rule.telemetry_only:
                        matches.append((rule.id, st["armed_peak"]))
                    st["cooldown"] = rule.cooldown_hops
                    st["armed_peak"] = 0.0
            elif st["armed_peak"] >= rule.threshold:
                if not rule.telemetry_only:
                    matches.append((rule.id, st["armed_peak"]))
                st["cooldown"] = rule.cooldown_hops
                st["armed_peak"] = 0.0

        for rule in freq_rules:
            st = self._rule_state(rule.id)
            if st["cooldown"] > 0:
                st["cooldown"] -= 1
            score = rule.score_frame(fg_bins)
            scores[rule.id] = score
            if st["cooldown"] > 0:
                st["hold"] = 0
                continue
            if score >= rule.threshold:
                st["hold"] += 1
                if st["hold"] >= rule.hold_hops:
                    if not rule.telemetry_only:
                        matches.append((rule.id, score))
                    st["cooldown"] = rule.cooldown_hops
                    st["hold"] = 0
            else:
                st["hold"] = 0

        return scores, matches

    def feed_samples(self, samples, sample_rules, freq_rules):
        buf = np.concatenate([self.remainder, np.asarray(samples, dtype=np.float32)])
        peak_scores = {}
        all_matches = []
        pos = 0
        while pos + WIN_SIZE <= buf.size:
            frame = buf[pos : pos + WIN_SIZE]
            scores, matches = self.step_frame(frame, sample_rules, freq_rules)
            for rid, val in scores.items():
                if val > peak_scores.get(rid, 0.0):
                    peak_scores[rid] = val
            all_matches.extend(matches)
            pos += HOP_SIZE
        self.remainder = buf[pos:]
        return peak_scores, all_matches


def _pw_cat_cmd(source):
    props = "node.passive=true,application.name=pangu-macro-audio"
    if source == "desktop":
        props = "stream.capture.sink=true," + props
    return [
        "pw-cat",
        "--record",
        "--raw",
        "--rate",
        str(SAMPLE_RATE),
        "--channels",
        "1",
        "--format",
        "s16",
        "--latency",
        "32ms",
        "-P",
        props,
        "-",
    ]


def cmd_record(args):
    stop = False

    def _handle_sig(_sig, _frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, _handle_sig)
    signal.signal(signal.SIGTERM, _handle_sig)

    proc = subprocess.Popen(_pw_cat_cmd(args.source), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    chunks = []
    total_samples = 0
    max_samples = int(round(float(args.max_seconds) * SAMPLE_RATE))
    chunk_bytes = HOP_SIZE * 2 * 4
    last_emit = 0.0
    try:
        while not stop and total_samples < max_samples:
            assert proc.stdout is not None
            ready, _, _ = select.select([proc.stdout], [], [], 0.15)
            if not ready:
                if proc.poll() is not None:
                    break
                continue
            raw = os.read(proc.stdout.fileno(), chunk_bytes)
            if not raw:
                break
            if len(raw) % 2 == 1:
                raw = raw[:-1]
            if not raw:
                continue
            arr = np.frombuffer(raw, dtype=np.int16).copy()
            chunks.append(arr)
            total_samples += arr.size
            now = time.monotonic()
            if now - last_emit >= 0.08:
                rms = float(np.sqrt(np.mean((arr.astype(np.float32) / 32768.0) ** 2)))
                print("RMS", round(min(1.0, rms * 4.0), 3), round(total_samples / SAMPLE_RATE, 2), flush=True)
                last_emit = now
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            proc.kill()

    if not chunks:
        return 1
    full = np.concatenate(chunks)[:max_samples]
    write_wav_atomic(args.output, full)
    meta = inspect_clip(args.output, do_autotrim=True)
    print("SAVED", json.dumps(meta), flush=True)
    return 0


def cmd_import(args):
    dest = Path(args.output)
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".imp-", suffix=".wav", dir=str(dest.parent))
    os.close(fd)
    try:
        res = subprocess.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-y",
                "-i",
                args.input,
                "-vn",
                "-ac",
                "1",
                "-ar",
                str(SAMPLE_RATE),
                "-t",
                "15",
                "-sample_fmt",
                "s16",
                "-f",
                "wav",
                tmp_name,
            ],
            check=False,
        )
        if res.returncode != 0:
            return res.returncode
        os.replace(tmp_name, str(dest))
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)
    meta = inspect_clip(dest, do_autotrim=True)
    print(json.dumps(meta), flush=True)
    return 0


def cmd_inspect(args):
    meta = inspect_clip(
        args.input,
        trim_start=args.trim_start,
        trim_end=args.trim_end,
        peaks_count=args.peaks,
        do_autotrim=args.autotrim,
    )
    print(json.dumps(meta), flush=True)
    return 0


def _compile_rules(config_path):
    data = json.loads(Path(config_path).read_text())
    rules = data.get("rules", []) if isinstance(data, dict) else data
    telemetry = bool(data.get("telemetry", False)) if isinstance(data, dict) else False
    by_source = {"desktop": ([], []), "mic": ([], [])}
    for entry in rules:
        rid = str(entry.get("id") or "")
        if not rid:
            continue
        source = entry.get("source") or "desktop"
        targets = ["desktop", "mic"] if source == "both" else (["mic"] if source == "mic" else ["desktop"])
        mode = entry.get("mode") or "sample"
        threshold = float(entry.get("threshold", 70)) / 100.0 if float(entry.get("threshold", 70)) > 1.0 else float(entry.get("threshold", 0.7))
        cooldown_ms = int(entry.get("cooldownMs", 1500))
        telemetry_only = bool(entry.get("telemetryOnly", False))
        if mode == "frequency":
            compiled = FrequencyRule(
                rid,
                min_hz=entry.get("minHz", 1000),
                max_hz=entry.get("maxHz", 3600),
                min_duration_ms=entry.get("minDurationMs", 60),
                threshold=threshold,
                cooldown_ms=cooldown_ms,
                telemetry_only=telemetry_only,
            )
            for tgt in targets:
                by_source[tgt][1].append(compiled)
        else:
            sample_path = entry.get("samplePath") or ""
            if not sample_path or not os.path.isfile(sample_path):
                continue
            try:
                wav = read_wav_mono(sample_path)
                compiled = SampleTemplate(
                    rid,
                    wav,
                    trim_start=entry.get("trimStart", 0.0),
                    trim_end=entry.get("trimEnd", 0.0),
                    band_filter=bool(entry.get("bandFilter", False)),
                    min_hz=entry.get("minHz", 80),
                    max_hz=entry.get("maxHz", 7600),
                    threshold=threshold,
                    cooldown_ms=cooldown_ms,
                    telemetry_only=telemetry_only,
                )
            except Exception as exc:
                print(f"sound_trigger: skipping {rid}: {exc}", file=sys.stderr, flush=True)
                continue
            for tgt in targets:
                by_source[tgt][0].append(compiled)
    return by_source, telemetry


def cmd_monitor(args):
    if not shutil.which("pw-cat"):
        print("sound_trigger: pw-cat not found", file=sys.stderr, flush=True)
        return 1

    stop = False

    def _handle_sig(_sig, _frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, _handle_sig)
    signal.signal(signal.SIGTERM, _handle_sig)

    procs = {}
    raw_tails = {"desktop": b"", "mic": b""}
    analyzers = {"desktop": StreamAnalyzer(), "mic": StreamAnalyzer()}
    by_source = {"desktop": ([], []), "mic": ([], [])}
    telemetry = bool(args.telemetry)
    last_mtime = -1
    last_reload_check = 0.0
    last_telemetry = 0.0
    rolling_scores = {}
    global_cooldown_until = {}

    def sync_streams():
        for src in ("desktop", "mic"):
            needed = bool(by_source[src][0] or by_source[src][1])
            proc = procs.get(src)
            alive = proc is not None and proc.poll() is None
            if needed and not alive:
                procs[src] = subprocess.Popen(_pw_cat_cmd(src), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                raw_tails[src] = b""
            elif not needed and proc is not None:
                proc.terminate()
                try:
                    proc.wait(timeout=0.5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                procs.pop(src, None)
                raw_tails[src] = b""

    try:
        while not stop:
            now = time.monotonic()
            if now - last_reload_check >= 0.25:
                last_reload_check = now
                try:
                    st = os.stat(args.config)
                    if st.st_mtime_ns != last_mtime:
                        last_mtime = st.st_mtime_ns
                        by_source, cfg_tel = _compile_rules(args.config)
                        telemetry = bool(args.telemetry or cfg_tel)
                        sync_streams()
                except FileNotFoundError:
                    pass
                except Exception as exc:
                    print(f"sound_trigger: reload failed: {exc}", file=sys.stderr, flush=True)

            sync_streams()
            fds = {proc.stdout.fileno(): src for src, proc in procs.items() if proc.stdout is not None}
            if not fds:
                time.sleep(0.15)
                continue

            ready, _, _ = select.select(list(fds.keys()), [], [], 0.12)
            for fd in ready:
                src = fds[fd]
                chunk = os.read(fd, HOP_SIZE * 2 * 4)
                if not chunk:
                    procs[src].wait()
                    procs.pop(src, None)
                    continue
                buf = raw_tails[src] + chunk
                even = (len(buf) // 2) * 2
                raw_tails[src] = buf[even:]
                if even == 0:
                    continue
                samples = np.frombuffer(buf[:even], dtype=np.int16).astype(np.float32) / 32768.0
                sample_rules, freq_rules = by_source[src]
                scores, matches = analyzers[src].feed_samples(samples, sample_rules, freq_rules)
                for rid, val in scores.items():
                    rolling_scores[rid] = max(val, rolling_scores.get(rid, 0.0) * 0.82)
                emit_now = time.monotonic()
                for rid, score in matches:
                    if emit_now < global_cooldown_until.get(rid, 0.0):
                        continue
                    # Prevent duplicate firing when source == "both".
                    rule_cd = 0.25
                    for rule in sample_rules + freq_rules:
                        if rule.id == rid:
                            rule_cd = rule.cooldown_hops * HOP_SIZE / SAMPLE_RATE
                            break
                    global_cooldown_until[rid] = emit_now + rule_cd
                    print(f"MATCH {rid} {round(score * 100)}", flush=True)

            now = time.monotonic()
            if telemetry and now - last_telemetry >= 0.12:
                last_telemetry = now
                payload = {
                    "levels": {
                        src: round(min(1.0, analyzers[src].last_rms * 4.0), 3)
                        for src in procs
                    },
                    "peakHz": {src: analyzers[src].last_peak_hz for src in procs},
                    "scores": {rid: round(val * 100) for rid, val in rolling_scores.items()},
                }
                print("TELEMETRY " + json.dumps(payload), flush=True)
                for rid in list(rolling_scores):
                    rolling_scores[rid] *= 0.78
    finally:
        for proc in procs.values():
            proc.terminate()
            try:
                proc.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                proc.kill()
    return 0


def main():
    parser = argparse.ArgumentParser(prog="sound_trigger.py")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_rec = sub.add_parser("record")
    p_rec.add_argument("output")
    p_rec.add_argument("--source", choices=["desktop", "mic"], default="desktop")
    p_rec.add_argument("--max-seconds", type=float, default=10.0)
    p_rec.set_defaults(func=cmd_record)

    p_imp = sub.add_parser("import")
    p_imp.add_argument("input")
    p_imp.add_argument("output")
    p_imp.set_defaults(func=cmd_import)

    p_ins = sub.add_parser("inspect")
    p_ins.add_argument("input")
    p_ins.add_argument("--trim-start", type=float, default=None)
    p_ins.add_argument("--trim-end", type=float, default=None)
    p_ins.add_argument("--peaks", type=int, default=96)
    p_ins.add_argument("--autotrim", action="store_true")
    p_ins.set_defaults(func=cmd_inspect)

    p_mon = sub.add_parser("monitor")
    p_mon.add_argument("--config", required=True)
    p_mon.add_argument("--telemetry", action="store_true")
    p_mon.set_defaults(func=cmd_monitor)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
