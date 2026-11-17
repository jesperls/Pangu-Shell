#!/usr/bin/env python3
import argparse
from dataclasses import dataclass, field
import glob
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import time
import zlib

import numpy as np

REDMEAN_MAX = float(255.0 * np.sqrt(8.0 + 255.0 / 256.0))
MAX_COALESCE_AREA = 262144  # Cap merged grim captures at 512x512 px so distant rules stay cheap.


def _wayland_env() -> dict[str, str]:
    env = os.environ.copy()
    if not env.get("WAYLAND_DISPLAY"):
        runtime = env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        for candidate in sorted(glob.glob(os.path.join(runtime, "wayland-*"))):
            if not candidate.endswith(".lock"):
                env["WAYLAND_DISPLAY"] = os.path.basename(candidate)
                break
    return env


def normalize_hex_color(raw: str) -> str:
    text = str(raw or "").strip()
    if text.startswith("#"):
        text = text[1:]
    if len(text) == 3 and all(c in "0123456789abcdefABCDEF" for c in text):
        text = "".join(c * 2 for c in text)
    if len(text) != 6 or not all(c in "0123456789abcdefABCDEF" for c in text):
        return ""
    return "#" + text.upper()


def hex_to_rgb(raw: str) -> np.ndarray | None:
    norm = normalize_hex_color(raw)
    if not norm:
        return None
    return np.array([int(norm[1:3], 16), int(norm[3:5], 16), int(norm[5:7], 16)], dtype=np.uint8)


def rgb_to_hex(rgb: np.ndarray) -> str:
    flat = np.asarray(rgb, dtype=np.uint8).reshape(-1)
    return f"#{int(flat[0]):02X}{int(flat[1]):02X}{int(flat[2]):02X}"


def parse_ppm(data: bytes) -> np.ndarray:
    if len(data) < 11 or data[:2] != b"P6":
        raise ValueError("Invalid PPM header")
    idx = 2
    tokens: list[int] = []
    n = len(data)
    while len(tokens) < 3 and idx < n:
        b = data[idx]
        if b in b" \t\r\n":
            idx += 1
            continue
        if b == ord("#"):
            nl = data.find(b"\n", idx)
            idx = n if nl == -1 else nl + 1
            continue
        start = idx
        while idx < n and data[idx] not in b" \t\r\n#":
            idx += 1
        tokens.append(int(data[start:idx]))
    if len(tokens) != 3 or idx >= n:
        raise ValueError("Truncated PPM header")
    width, height, maxval = tokens
    if width <= 0 or height <= 0 or maxval <= 0 or maxval > 65535:
        raise ValueError("Invalid PPM dimensions")
    idx += 1  # P6 spec mandates exactly one whitespace byte before raster payload.
    expected = width * height * 3
    if maxval > 255:
        raw16 = np.frombuffer(data, dtype=">u2", count=expected, offset=idx)
        arr = np.rint(raw16.astype(np.float32) * (255.0 / maxval)).astype(np.uint8)
        return arr.reshape((height, width, 3))
    if len(data) - idx < expected:
        raise ValueError("Truncated PPM raster")
    arr = np.frombuffer(data, dtype=np.uint8, count=expected, offset=idx).copy()
    return arr.reshape((height, width, 3))


def encode_png(rgb: np.ndarray) -> bytes:
    arr = np.asarray(rgb, dtype=np.uint8)
    if arr.ndim != 3 or arr.shape[2] != 3:
        raise ValueError("Expected (H, W, 3) uint8 array")
    h, w, _ = arr.shape
    scanlines = np.concatenate([np.zeros((h, 1), dtype=np.uint8), arr.reshape(h, w * 3)], axis=1)

    def chunk(tag: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    idat = zlib.compress(scanlines.tobytes(), level=1)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def write_png_atomic(path: Path, rgb: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    tmp.write_bytes(encode_png(rgb))
    os.replace(tmp, path)


def read_image_rgb(path: Path) -> np.ndarray:
    raw = path.read_bytes()
    if raw[:2] == b"P6":
        return parse_ppm(raw)
    if raw[:8] == b"\x89PNG\r\n\x1a\n":
        pos = 8
        w = h = color_type = bit_depth = interlace = -1
        idat_parts: list[bytes] = []
        while pos + 8 <= len(raw):
            length, tag = struct.unpack(">I4s", raw[pos : pos + 8])
            payload = raw[pos + 8 : pos + 8 + length]
            pos += 12 + length
            if tag == b"IHDR" and len(payload) >= 13:
                w, h, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", payload[:13])
            elif tag == b"IDAT":
                idat_parts.append(payload)
            elif tag == b"IEND":
                break
        if w > 0 and h > 0 and bit_depth == 8 and color_type in (2, 6) and interlace == 0 and idat_parts:
            channels = 3 if color_type == 2 else 4
            decompressed = zlib.decompress(b"".join(idat_parts))
            stride = 1 + w * channels
            if len(decompressed) == h * stride:
                rows = np.frombuffer(decompressed, dtype=np.uint8).reshape((h, stride))
                if np.all(rows[:, 0] == 0):
                    pixels = rows[:, 1:].reshape((h, w, channels))[:, :, :3].copy()
                    return pixels
    proc = subprocess.run(
        ["magick", str(path), "-depth", "8", "ppm:-"],
        capture_output=True,
        timeout=4.0,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", errors="replace").strip() or "Failed to decode image")
    return parse_ppm(proc.stdout)


def perceptual_dist_pct(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    af = np.asarray(a, dtype=np.float32)
    bf = np.asarray(b, dtype=np.float32)
    rmean = 0.5 * (af[..., 0] + bf[..., 0])
    dr = af[..., 0] - bf[..., 0]
    dg = af[..., 1] - bf[..., 1]
    db = af[..., 2] - bf[..., 2]
    sq = (2.0 + rmean / 256.0) * (dr * dr) + 4.0 * (dg * dg) + (2.0 + (255.0 - rmean) / 256.0) * (db * db)
    return np.clip(np.sqrt(np.maximum(sq, 0.0)) * (100.0 / REDMEAN_MAX), 0.0, 100.0)


def extract_distinct_colors(
    rgb: np.ndarray,
    max_colors: int = 4,
    min_sep_pct: float = 10.0,
    min_share_pct: float = 1.5,
) -> list[dict]:
    pixels = np.asarray(rgb, dtype=np.uint8).reshape((-1, 3))
    total = int(pixels.shape[0])
    if total == 0:
        return []
    if total == 1 or max_colors <= 1:
        mean_px = np.rint(pixels.mean(axis=0)).astype(np.uint8)
        return [{"hex": rgb_to_hex(mean_px), "coverage": 100.0}]

    q = (pixels.astype(np.int32) >> 4)
    keys = (q[:, 0] << 8) | (q[:, 1] << 4) | q[:, 2]
    uniq_keys, inverse, counts = np.unique(keys, return_inverse=True, return_counts=True)
    order = np.argsort(-counts)

    sums = np.zeros((len(uniq_keys), 3), dtype=np.float64)
    np.add.at(sums, inverse, pixels.astype(np.float64))

    unassigned = np.ones(total, dtype=bool)
    chosen: list[dict] = []
    radius = max(6.0, float(min_sep_pct))
    for idx in order:
        seed = np.rint(sums[idx] / int(counts[idx])).astype(np.uint8)
        avail_idx = np.flatnonzero(unassigned)
        if avail_idx.size == 0:
            break
        dists = perceptual_dist_pct(pixels[avail_idx], seed[None, :])
        near = avail_idx[dists <= radius]
        if near.size == 0:
            continue
        share = 100.0 * near.size / total
        if chosen and share < min_share_pct:
            continue
        center = np.rint(pixels[near].mean(axis=0)).astype(np.uint8)
        hex_code = rgb_to_hex(center)
        if any(entry["hex"] == hex_code for entry in chosen):
            unassigned[near] = False
            continue
        unassigned[near] = False
        chosen.append({"hex": hex_code, "coverage": round(share, 1)})
        if len(chosen) >= max_colors:
            break

    if not chosen:
        mean_px = np.rint(pixels.mean(axis=0)).astype(np.uint8)
        return [{"hex": rgb_to_hex(mean_px), "coverage": 100.0}]
    return chosen


def capture_region(x: int, y: int, width: int, height: int, env: dict[str, str] | None = None) -> np.ndarray | None:
    w = max(1, int(width))
    h = max(1, int(height))
    geom = f"{int(x)},{int(y)} {w}x{h}"
    try:
        proc = subprocess.run(
            ["grim", "-s", "1", "-g", geom, "-t", "ppm", "-"],
            env=env or _wayland_env(),
            capture_output=True,
            timeout=2.0,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0 or not proc.stdout:
        return None
    try:
        return parse_ppm(proc.stdout)
    except ValueError:
        return None


def _resize_nearest(arr: np.ndarray, target_h: int, target_w: int) -> np.ndarray:
    if arr.shape[0] == target_h and arr.shape[1] == target_w:
        return arr
    yi = np.minimum((np.arange(target_h) * arr.shape[0]) // max(1, target_h), arr.shape[0] - 1)
    xi = np.minimum((np.arange(target_w) * arr.shape[1]) // max(1, target_w), arr.shape[1] - 1)
    return arr[yi][:, xi]


@dataclass
class PixelRule:
    id: str
    target_mode: str = "pixel"
    watch_mode: str = "color"
    x: int = 0
    y: int = 0
    width: int = 1
    height: int = 1
    colors: list[tuple[str, np.ndarray]] = field(default_factory=list)
    color_logic: str = "any"
    color_tolerance: float = 12.0
    change_ref: str = "previous"
    baseline_path: str = ""
    change_threshold: float = 12.0
    area_threshold: float = 15.0
    fire_on_edge: bool = True
    min_hold_ms: int = 0
    interval_ms: int = 150
    cooldown_ms: int = 1000
    telemetry_only: bool = False

    @property
    def capture_w(self) -> int:
        return 1 if self.target_mode == "pixel" else max(1, self.width)

    @property
    def capture_h(self) -> int:
        return 1 if self.target_mode == "pixel" else max(1, self.height)

    def state_signature(self) -> tuple:
        return (
            self.target_mode,
            self.watch_mode,
            self.x,
            self.y,
            self.capture_w,
            self.capture_h,
            self.change_ref,
            self.baseline_path,
            self.telemetry_only,
        )


@dataclass
class RuleState:
    signature: tuple = ()
    prev_frame: np.ndarray | None = None
    auto_baseline: np.ndarray | None = None
    cached_baseline: np.ndarray | None = None
    cached_baseline_key: tuple[str, int] = ("", -1)
    hold_since: float | None = None
    armed: bool = True
    last_fire_s: float = -1e9
    next_poll_s: float = 0.0
    last_preview_s: float = -1e9


def compile_rule(raw: dict) -> PixelRule | None:
    if not isinstance(raw, dict) or not raw.get("id"):
        return None
    target_mode = raw.get("targetMode") if raw.get("targetMode") in ("pixel", "area") else "pixel"
    watch_mode = raw.get("watchMode") if raw.get("watchMode") in ("color", "change") else "color"
    color_logic = raw.get("colorLogic") if raw.get("colorLogic") in ("any", "all", "none") else "any"
    change_ref = raw.get("changeRef") if raw.get("changeRef") in ("previous", "baseline") else "previous"

    colors: list[tuple[str, np.ndarray]] = []
    seen_hex: set[str] = set()
    for item in raw.get("colors") or []:
        hx = normalize_hex_color(item)
        if hx and hx not in seen_hex:
            rgb = hex_to_rgb(hx)
            if rgb is not None:
                seen_hex.add(hx)
                colors.append((hx, rgb))

    return PixelRule(
        id=str(raw["id"]),
        target_mode=target_mode,
        watch_mode=watch_mode,
        x=int(np.clip(int(raw.get("x", 0)), -32768, 32767)),
        y=int(np.clip(int(raw.get("y", 0)), -32768, 32767)),
        width=1 if target_mode == "pixel" else int(np.clip(int(raw.get("width", 64)), 1, 8192)),
        height=1 if target_mode == "pixel" else int(np.clip(int(raw.get("height", 64)), 1, 8192)),
        colors=colors,
        color_logic=color_logic,
        color_tolerance=float(np.clip(float(raw.get("colorTolerance", 12)), 1.0, 50.0)),
        change_ref=change_ref,
        baseline_path=str(raw.get("baselinePath") or ""),
        change_threshold=float(np.clip(float(raw.get("changeThreshold", 12)), 1.0, 100.0)),
        area_threshold=float(np.clip(float(raw.get("areaThreshold", 15)), 1.0, 100.0)),
        fire_on_edge=bool(raw.get("fireOnEdge", True)),
        min_hold_ms=int(np.clip(int(raw.get("minHoldMs", 0)), 0, 10000)),
        interval_ms=int(np.clip(int(raw.get("intervalMs", 150)), 50, 10000)),
        cooldown_ms=int(np.clip(int(raw.get("cooldownMs", 1000)), 100, 300000)),
        telemetry_only=bool(raw.get("telemetryOnly", False)),
    )


def load_config(path: Path) -> tuple[list[PixelRule], bool]:
    data = json.loads(path.read_text())
    telemetry = bool(data.get("telemetry", False))
    rules: list[PixelRule] = []
    for entry in data.get("rules") or []:
        compiled = compile_rule(entry)
        if compiled is not None:
            rules.append(compiled)
    return rules, telemetry


def _load_baseline_for(rule: PixelRule, state: RuleState, shape: tuple[int, int, int]) -> np.ndarray | None:
    if rule.baseline_path:
        bpath = Path(rule.baseline_path)
        try:
            st = bpath.stat()
            key = (rule.baseline_path, st.st_mtime_ns)
            if state.cached_baseline is None or state.cached_baseline_key != key:
                state.cached_baseline = read_image_rgb(bpath)
                state.cached_baseline_key = key
            return _resize_nearest(state.cached_baseline, shape[0], shape[1])
        except Exception:
            pass
    return None


def evaluate_frame(rule: PixelRule, state: RuleState, frame: np.ndarray, now_s: float) -> tuple[dict, str | None]:
    sig = rule.state_signature()
    if state.signature != sig:
        state.signature = sig
        state.prev_frame = None
        state.auto_baseline = None
        state.hold_since = None
        state.armed = True

    mean_rgb = np.rint(frame.reshape((-1, 3)).mean(axis=0)).astype(np.uint8)
    live_hex = rgb_to_hex(mean_rgb)
    per_color: dict[str, float] = {}
    coverage_pct = 0.0
    score = 0.0
    threshold = rule.area_threshold
    raw_match = False
    detail_label = ""

    if rule.watch_mode == "color":
        if not rule.colors:
            threshold = rule.area_threshold if rule.target_mode == "area" else (100.0 - rule.color_tolerance)
        elif rule.target_mode == "pixel":
            px = mean_rgb[None, :]
            dists: list[tuple[str, float]] = []
            for hx, rgb_c in rule.colors:
                d = float(perceptual_dist_pct(px, rgb_c[None, :])[0])
                dists.append((hx, d))
                per_color[hx] = round(max(0.0, 100.0 - d), 1)
            best_hex, min_d = min(dists, key=lambda item: item[1])
            max_d = max(d for _, d in dists)
            if rule.color_logic == "any":
                score = max(0.0, 100.0 - min_d)
                threshold = 100.0 - rule.color_tolerance
                raw_match = min_d <= rule.color_tolerance
                coverage_pct = score
                detail_label = f"Pixel {best_hex} ({round(score)}%)"
            elif rule.color_logic == "all":
                score = max(0.0, 100.0 - max_d)
                threshold = 100.0 - rule.color_tolerance
                raw_match = max_d <= rule.color_tolerance
                coverage_pct = score
                detail_label = f"Pixel colors ({round(score)}%)"
            else:
                score = min(100.0, min_d)
                threshold = rule.color_tolerance
                raw_match = min_d > rule.color_tolerance
                coverage_pct = max(0.0, 100.0 - min_d)
                detail_label = f"Pixel left {rule.colors[0][0]} (Δ{round(min_d)}%)"
        else:
            color_stack = np.stack([rgb_c for _, rgb_c in rule.colors], axis=0)
            dists_map = perceptual_dist_pct(frame[None, :, :, :], color_stack[:, None, None, :])
            masks = dists_map <= rule.color_tolerance
            per_pct = [100.0 * float(masks[i].mean()) for i in range(len(rule.colors))]
            for idx, (hx, _) in enumerate(rule.colors):
                per_color[hx] = round(per_pct[idx], 1)
            union_pct = 100.0 * float(np.any(masks, axis=0).mean())
            coverage_pct = union_pct
            if rule.color_logic == "any":
                score = union_pct
                threshold = rule.area_threshold
                raw_match = union_pct >= rule.area_threshold
                top_hx = rule.colors[int(np.argmax(per_pct))][0]
                detail_label = f"Area {top_hx} ({round(union_pct)}%)"
            elif rule.color_logic == "all":
                min_req = min(2.0, rule.area_threshold / max(1, len(rule.colors)))
                all_present = all(bool(masks[i].any()) and per_pct[i] >= min_req for i in range(len(rule.colors)))
                threshold = rule.area_threshold
                raw_match = all_present and union_pct >= rule.area_threshold
                score = union_pct if all_present else min(union_pct, max(0.0, rule.area_threshold - 1.0))
                detail_label = f"Area all colors ({round(union_pct)}%)"
            else:
                score = max(0.0, 100.0 - union_pct)
                threshold = max(0.0, 100.0 - rule.area_threshold)
                raw_match = union_pct < rule.area_threshold
                detail_label = f"Area colors gone ({round(union_pct, 1)}%)"
    else:
        ref_frame: np.ndarray | None = None
        if rule.change_ref == "baseline":
            ref_frame = _load_baseline_for(rule, state, frame.shape)
            if ref_frame is None:
                if state.auto_baseline is None or state.auto_baseline.shape != frame.shape:
                    state.auto_baseline = frame.copy()
                    threshold = rule.area_threshold if rule.target_mode == "area" else rule.change_threshold
                    return (
                        {
                            "score": 0.0,
                            "threshold": round(threshold, 1),
                            "matched": False,
                            "hex": live_hex,
                            "coverage": 0.0,
                            "perColor": {},
                        },
                        None,
                    )
                ref_frame = state.auto_baseline
        else:
            if state.prev_frame is None or state.prev_frame.shape != frame.shape:
                state.prev_frame = frame.copy()
                threshold = rule.area_threshold if rule.target_mode == "area" else rule.change_threshold
                return (
                    {
                        "score": 0.0,
                        "threshold": round(threshold, 1),
                        "matched": False,
                        "hex": live_hex,
                        "coverage": 0.0,
                        "perColor": {},
                    },
                    None,
                )
            ref_frame = state.prev_frame

        if rule.target_mode == "pixel":
            ref_px = np.rint(ref_frame.reshape((-1, 3)).mean(axis=0)).astype(np.uint8)[None, :]
            delta = float(perceptual_dist_pct(mean_rgb[None, :], ref_px)[0])
            score = delta
            coverage_pct = delta
            threshold = rule.change_threshold
            raw_match = delta >= rule.change_threshold
            detail_label = f"Pixel change ({round(delta)}%)"
        else:
            delta_map = perceptual_dist_pct(frame, ref_frame)
            changed_pct = 100.0 * float((delta_map >= rule.change_threshold).mean())
            score = changed_pct
            coverage_pct = changed_pct
            threshold = rule.area_threshold
            raw_match = changed_pct >= rule.area_threshold
            detail_label = f"Area change ({round(changed_pct)}%)"

    fired: str | None = None
    if not raw_match:
        state.hold_since = None
        state.armed = True
        if rule.watch_mode == "change" and rule.change_ref == "previous":
            state.prev_frame = frame.copy()
    else:
        if state.hold_since is None:
            state.hold_since = now_s
        held_ms = (now_s - state.hold_since) * 1000.0
        hold_ready = held_ms >= rule.min_hold_ms
        cooldown_ready = (now_s - state.last_fire_s) * 1000.0 >= rule.cooldown_ms
        edge_ready = state.armed if rule.fire_on_edge else True

        if rule.telemetry_only:
            if rule.watch_mode == "change" and rule.change_ref == "previous" and held_ms >= max(rule.min_hold_ms, 450):
                state.prev_frame = frame.copy()
                state.hold_since = None
        elif hold_ready and edge_ready and cooldown_ready:
            fired = detail_label
            state.last_fire_s = now_s
            if rule.watch_mode == "change" and rule.change_ref == "previous":
                state.prev_frame = frame.copy()
                state.hold_since = None
                state.armed = True
            elif rule.fire_on_edge:
                state.armed = False

    telemetry_entry = {
        "score": round(float(score), 1),
        "threshold": round(float(threshold), 1),
        "matched": bool(raw_match),
        "hex": live_hex,
        "coverage": round(float(coverage_pct), 1),
        "perColor": per_color,
    }
    return telemetry_entry, fired


def group_capture_batches(due_rules: list[PixelRule]) -> list[tuple[int, int, int, int, list[PixelRule]]]:
    batches: list[list] = []
    for rule in due_rules:
        rx, ry, rw, rh = rule.x, rule.y, rule.capture_w, rule.capture_h
        placed = False
        for batch in batches:
            bx, by, bw, bh, members, sum_area = batch
            nx0 = min(bx, rx)
            ny0 = min(by, ry)
            nx1 = max(bx + bw, rx + rw)
            ny1 = max(by + bh, ry + rh)
            union_area = (nx1 - nx0) * (ny1 - ny0)
            next_sum = sum_area + rw * rh
            if union_area <= MAX_COALESCE_AREA and union_area <= max(4096, 4 * next_sum):
                batch[0], batch[1], batch[2], batch[3] = nx0, ny0, nx1 - nx0, ny1 - ny0
                members.append(rule)
                batch[5] = next_sum
                placed = True
                break
        if not placed:
            batches.append([rx, ry, rw, rh, [rule], rw * rh])
    return [(b[0], b[1], b[2], b[3], b[4]) for b in batches]


def cmd_sample(args: argparse.Namespace) -> int:
    frame = capture_region(args.x, args.y, args.width, args.height)
    if frame is None:
        print("Failed to capture region", file=sys.stderr)
        return 1
    mean_rgb = np.rint(frame.reshape((-1, 3)).mean(axis=0)).astype(np.uint8)
    colors = extract_distinct_colors(frame, max_colors=args.max_colors, min_sep_pct=args.min_sep)
    preview_path = ""
    if args.preview_out:
        out = Path(args.preview_out)
        write_png_atomic(out, frame)
        preview_path = str(out)
    print(
        json.dumps(
            {
                "x": args.x,
                "y": args.y,
                "width": args.width,
                "height": args.height,
                "hex": rgb_to_hex(mean_rgb),
                "colors": colors,
                "previewPath": preview_path,
            }
        ),
        flush=True,
    )
    return 0


def cmd_snapshot(args: argparse.Namespace) -> int:
    frame = capture_region(args.x, args.y, args.width, args.height)
    if frame is None:
        print("Failed to capture baseline snapshot", file=sys.stderr)
        return 1
    out = Path(args.output)
    write_png_atomic(out, frame)
    mean_rgb = np.rint(frame.reshape((-1, 3)).mean(axis=0)).astype(np.uint8)
    print(
        json.dumps(
            {
                "baselinePath": str(out),
                "width": int(frame.shape[1]),
                "height": int(frame.shape[0]),
                "hex": rgb_to_hex(mean_rgb),
            }
        ),
        flush=True,
    )
    return 0


def cmd_monitor(args: argparse.Namespace) -> int:
    cfg_path = Path(args.config)
    preview_dir = cfg_path.parent
    env = _wayland_env()

    stop = False

    def _on_sig(_signum, _frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, _on_sig)
    signal.signal(signal.SIGTERM, _on_sig)

    last_mtime_ns = -1
    rules: list[PixelRule] = []
    telemetry_enabled = False
    states: dict[str, RuleState] = {}
    telemetry_snapshot: dict[str, dict] = {}
    last_telemetry_emit_s = 0.0

    while not stop:
        try:
            st = cfg_path.stat()
            if st.st_mtime_ns != last_mtime_ns:
                last_mtime_ns = st.st_mtime_ns
                rules, telemetry_enabled = load_config(cfg_path)
                active_ids = {r.id for r in rules}
                states = {rid: s for rid, s in states.items() if rid in active_ids}
                telemetry_snapshot = {rid: t for rid, t in telemetry_snapshot.items() if rid in active_ids}
        except FileNotFoundError:
            rules = []
            telemetry_enabled = False
        except Exception as exc:
            print(f"Config reload error: {exc}", file=sys.stderr)

        if not rules:
            time.sleep(0.2)
            continue

        now_s = time.monotonic()
        due_rules: list[PixelRule] = []
        earliest_next_s = now_s + 0.5

        for rule in rules:
            st_obj = states.setdefault(rule.id, RuleState())
            if now_s >= st_obj.next_poll_s:
                due_rules.append(rule)
                st_obj.next_poll_s = now_s + (rule.interval_ms / 1000.0)
            if st_obj.next_poll_s < earliest_next_s:
                earliest_next_s = st_obj.next_poll_s

        if due_rules:
            for bx, by, bw, bh, members in group_capture_batches(due_rules):
                batch_img = capture_region(bx, by, bw, bh, env=env)
                eval_s = time.monotonic()
                if batch_img is None:
                    for rule in members:
                        telemetry_snapshot[rule.id] = {
                            "score": 0.0,
                            "threshold": 0.0,
                            "matched": False,
                            "hex": "",
                            "coverage": 0.0,
                            "perColor": {},
                            "error": "capture_failed",
                        }
                    continue

                scale_x = batch_img.shape[1] / max(1, bw)
                scale_y = batch_img.shape[0] / max(1, bh)
                for rule in members:
                    if len(members) == 1:
                        sub = batch_img
                    else:
                        sx0 = int(round((rule.x - bx) * scale_x))
                        sy0 = int(round((rule.y - by) * scale_y))
                        sx1 = max(sx0 + 1, int(round((rule.x + rule.capture_w - bx) * scale_x)))
                        sy1 = max(sy0 + 1, int(round((rule.y + rule.capture_h - by) * scale_y)))
                        sub = batch_img[sy0:sy1, sx0:sx1]
                        if sub.size == 0:
                            continue

                    st_obj = states[rule.id]
                    tel_entry, fired_detail = evaluate_frame(rule, st_obj, sub, eval_s)

                    if telemetry_enabled and rule.target_mode == "area":
                        safe_id = "".join(c if c.isalnum() or c in "_-" else "_" for c in rule.id)
                        prev_file = preview_dir / f"macro-pixel-preview-{safe_id}.png"
                        if eval_s - st_obj.last_preview_s >= 0.45:
                            try:
                                write_png_atomic(prev_file, sub)
                                st_obj.last_preview_s = eval_s
                            except OSError:
                                pass
                        if st_obj.last_preview_s > 0:
                            tel_entry["previewPath"] = str(prev_file)
                            tel_entry["previewStamp"] = int(st_obj.last_preview_s * 1000)

                    telemetry_snapshot[rule.id] = tel_entry
                    if fired_detail is not None:
                        print(f"MATCH {rule.id} {fired_detail}", flush=True)

            emit_now = time.monotonic()
            if telemetry_enabled and emit_now - last_telemetry_emit_s >= 0.08:
                last_telemetry_emit_s = emit_now
                print("TELEMETRY " + json.dumps({"rules": telemetry_snapshot}), flush=True)

        sleep_s = max(0.01, min(0.25, earliest_next_s - time.monotonic()))
        time.sleep(sleep_s)

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Pangu macro pixel & area watcher")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_sample = sub.add_parser("sample")
    p_sample.add_argument("--x", type=int, required=True)
    p_sample.add_argument("--y", type=int, required=True)
    p_sample.add_argument("--width", type=int, default=1)
    p_sample.add_argument("--height", type=int, default=1)
    p_sample.add_argument("--max-colors", type=int, default=4)
    p_sample.add_argument("--min-sep", type=float, default=10.0)
    p_sample.add_argument("--preview-out", type=str, default="")

    p_snap = sub.add_parser("snapshot")
    p_snap.add_argument("--x", type=int, required=True)
    p_snap.add_argument("--y", type=int, required=True)
    p_snap.add_argument("--width", type=int, default=1)
    p_snap.add_argument("--height", type=int, default=1)
    p_snap.add_argument("--output", type=str, required=True)

    p_mon = sub.add_parser("monitor")
    p_mon.add_argument("--config", type=str, required=True)

    args = parser.parse_args()
    if args.cmd == "sample":
        return cmd_sample(args)
    if args.cmd == "snapshot":
        return cmd_snapshot(args)
    return cmd_monitor(args)


if __name__ == "__main__":
    sys.exit(main())
