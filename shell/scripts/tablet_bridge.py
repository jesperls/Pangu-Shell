#!/usr/bin/env python3
import argparse
import json
import os
import re
import select
import signal
import struct
import subprocess
import sys
import time

try:
    import evdev
    from evdev import AbsInfo, UInput, ecodes as e
except ImportError:  # unit tests can import pure helpers without evdev
    evdev = None
    AbsInfo = None
    UInput = None
    e = None

DEFAULT_CONFIG = {
    "deviceSerial": "",
    "wirelessAddress": "",
    "wirelessAutoConnect": True,
    "inputMode": "pen",
    "rotation": 0,
    "flipX": False,
    "flipY": False,
    "aspectMode": "fit-tablet",
    "targetAspect": 16.0 / 9.0,
    "areaScale": 1.0,
    "areaOffsetX": 0.0,
    "areaOffsetY": 0.0,
    "pressureEnabled": True,
    "pressureGamma": 1.0,
    "pressureMin": 0.0,
    "pressureMax": 1.0,
    "tiltEnabled": True,
    "smoothing": 0,
    "eraserEnabled": True,
    "swapStylusButtons": False,
    "suppressPen": True,
    "suppressTouch": True,
    "keepAwake": True,
    "touchpadSpeed": 1.0,
    "touchpadRotation": "auto",
    "touchpadPalmRejectMs": 350,
    "telemetry": False,
}

PEN_NAME_HINTS = ("pen", "wacom", "stylus", "digitizer", "emr", "emp", "s_pen", "spen")
TOUCH_NAME_HINTS = ("touchscreen", "_ts_", "touch", "finger")
PEN_KEY_NAMES = {
    "BTN_DIGI",
    "BTN_TOOL_PEN",
    "BTN_TOOL_RUBBER",
    "BTN_TOOL_BRUSH",
    "BTN_TOOL_PENCIL",
    "BTN_TOOL_AIRBRUSH",
    "BTN_STYLUS",
    "BTN_STYLUS2",
}


def clamp(value: float, lo: float, hi: float) -> float:
    return lo if value < lo else (hi if value > hi else value)


def normalize_config(raw: dict | None) -> dict:
    cfg = dict(DEFAULT_CONFIG)
    if not isinstance(raw, dict):
        return cfg

    serial = raw.get("deviceSerial", "")
    cfg["deviceSerial"] = str(serial).strip() if serial is not None else ""

    waddr = raw.get("wirelessAddress", "")
    cfg["wirelessAddress"] = str(waddr).strip() if waddr is not None else ""
    cfg["wirelessAutoConnect"] = bool(raw.get("wirelessAutoConnect", True))

    mode = str(raw.get("inputMode", "pen") or "pen").strip().lower()
    cfg["inputMode"] = mode if mode in ("pen", "hybrid", "touchpad") else "pen"

    rot = int(raw.get("rotation", 0) or 0) % 360
    cfg["rotation"] = rot if rot in (0, 90, 180, 270) else 0
    cfg["flipX"] = bool(raw.get("flipX", False))
    cfg["flipY"] = bool(raw.get("flipY", False))

    aspect_mode = str(raw.get("aspectMode", "fit-tablet") or "fit-tablet")
    cfg["aspectMode"] = aspect_mode if aspect_mode in ("stretch", "fit-tablet", "fit-screen") else "fit-tablet"

    try:
        ta = float(raw.get("targetAspect", DEFAULT_CONFIG["targetAspect"]))
        cfg["targetAspect"] = ta if 0.1 <= ta <= 20.0 else DEFAULT_CONFIG["targetAspect"]
    except (TypeError, ValueError):
        cfg["targetAspect"] = DEFAULT_CONFIG["targetAspect"]

    try:
        cfg["areaScale"] = clamp(float(raw.get("areaScale", 1.0)), 0.25, 1.0)
    except (TypeError, ValueError):
        cfg["areaScale"] = 1.0
    try:
        cfg["areaOffsetX"] = clamp(float(raw.get("areaOffsetX", 0.0)), -0.5, 0.5)
    except (TypeError, ValueError):
        cfg["areaOffsetX"] = 0.0
    try:
        cfg["areaOffsetY"] = clamp(float(raw.get("areaOffsetY", 0.0)), -0.5, 0.5)
    except (TypeError, ValueError):
        cfg["areaOffsetY"] = 0.0

    cfg["pressureEnabled"] = bool(raw.get("pressureEnabled", True))
    try:
        cfg["pressureGamma"] = clamp(float(raw.get("pressureGamma", 1.0)), 0.25, 3.0)
    except (TypeError, ValueError):
        cfg["pressureGamma"] = 1.0
    try:
        p_min = clamp(float(raw.get("pressureMin", 0.0)), 0.0, 0.45)
    except (TypeError, ValueError):
        p_min = 0.0
    try:
        p_max = clamp(float(raw.get("pressureMax", 1.0)), 0.3, 1.0)
    except (TypeError, ValueError):
        p_max = 1.0
    if p_max - p_min < 0.05:
        p_max = min(1.0, p_min + 0.05)
    cfg["pressureMin"] = p_min
    cfg["pressureMax"] = p_max

    cfg["tiltEnabled"] = bool(raw.get("tiltEnabled", True))
    try:
        cfg["smoothing"] = int(clamp(float(raw.get("smoothing", 0)), 0, 10))
    except (TypeError, ValueError):
        cfg["smoothing"] = 0

    cfg["eraserEnabled"] = bool(raw.get("eraserEnabled", True))
    cfg["swapStylusButtons"] = bool(raw.get("swapStylusButtons", False))
    cfg["suppressPen"] = bool(raw.get("suppressPen", True))
    cfg["suppressTouch"] = bool(raw.get("suppressTouch", True))
    cfg["keepAwake"] = bool(raw.get("keepAwake", True))
    try:
        cfg["touchpadSpeed"] = clamp(float(raw.get("touchpadSpeed", 1.0)), 0.4, 2.5)
    except (TypeError, ValueError):
        cfg["touchpadSpeed"] = 1.0
    tp_rot = str(raw.get("touchpadRotation", "auto") or "auto").strip().lower()
    cfg["touchpadRotation"] = tp_rot if tp_rot in ("auto", "0", "90", "180", "270") else "auto"
    try:
        cfg["touchpadPalmRejectMs"] = int(clamp(float(raw.get("touchpadPalmRejectMs", 350)), 0, 1000))
    except (TypeError, ValueError):
        cfg["touchpadPalmRejectMs"] = 350
    cfg["telemetry"] = bool(raw.get("telemetry", False))
    return cfg


def is_wireless_serial(serial: str) -> bool:
    return ":" in (serial or "")


def parse_wifi_ip(output: str) -> str:
    wlan_ip = ""
    fallback_ip = ""
    for line in output.splitlines():
        m = re.search(r"\b(\S+)\s+inet\s+(\d+\.\d+\.\d+\.\d+)/", line)
        if not m:
            continue
        iface, ip = m.group(1), m.group(2)
        if ip.startswith("127."):
            continue
        if iface.startswith("wlan"):
            wlan_ip = ip
            break
        if not fallback_ip:
            fallback_ip = ip
    return wlan_ip or fallback_ip


def parse_adb_devices(output: str) -> list[dict]:
    devices = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith("List of devices") or line.startswith("*"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        serial, state = parts[0], parts[1]
        model = ""
        for token in parts[2:]:
            if token.startswith("model:"):
                model = token.split(":", 1)[1].replace("_", " ")
                break
        devices.append({"serial": serial, "state": state, "model": model})
    return devices


def parse_getevent_devices(output: str) -> list[dict]:
    devices = []
    current = None
    section = ""

    for raw_line in output.splitlines():
        m_dev = re.match(r"^add device \d+:\s+(\S+)", raw_line)
        if m_dev:
            current = {"path": m_dev.group(1), "name": "", "keys": set(), "abs": {}, "props": set()}
            devices.append(current)
            section = ""
            continue
        if current is None:
            continue

        stripped = raw_line.strip()
        m_name = re.match(r'^name:\s+"(.*)"$', stripped)
        if m_name:
            current["name"] = m_name.group(1)
            continue

        if stripped.startswith("KEY ("):
            section = "KEY"
            rest = stripped.split(":", 1)[1] if ":" in stripped else ""
            for tok in rest.split():
                current["keys"].add(tok.rstrip("*"))
            continue
        if stripped.startswith("ABS ("):
            section = "ABS"
            stripped = stripped.split(":", 1)[1].strip() if ":" in stripped else ""
        elif stripped.startswith("input props:"):
            section = "PROPS"
            continue
        elif re.match(r"^[A-Z]+\s+\([0-9a-fA-F]+\):", stripped):
            section = "OTHER"
            continue

        if section == "KEY":
            for tok in stripped.split():
                current["keys"].add(tok.rstrip("*"))
        elif section == "ABS":
            m_abs = re.match(
                r"^([A-Z0-9_]+)\s*:\s*value\s+(-?\d+),\s*min\s+(-?\d+),\s*max\s+(-?\d+),\s*fuzz\s+(-?\d+),\s*flat\s+(-?\d+),\s*resolution\s+(-?\d+)",
                stripped,
            )
            if m_abs:
                current["abs"][m_abs.group(1)] = {
                    "value": int(m_abs.group(2)),
                    "min": int(m_abs.group(3)),
                    "max": int(m_abs.group(4)),
                    "fuzz": int(m_abs.group(5)),
                    "flat": int(m_abs.group(6)),
                    "resolution": int(m_abs.group(7)),
                }
        elif section == "PROPS":
            if stripped and stripped != "<none>":
                current["props"].add(stripped)

    return devices


def select_pen_device(devices: list[dict]) -> dict | None:
    best = None
    best_score = -1
    for dev in devices:
        axes = dev.get("abs", {})
        if "ABS_X" not in axes or "ABS_Y" not in axes:
            continue
        keys = dev.get("keys", set())
        has_pen_key = bool(keys & PEN_KEY_NAMES)
        has_pressure = "ABS_PRESSURE" in axes
        if not has_pen_key and not has_pressure:
            continue

        score = 0
        if has_pen_key:
            score += 40
        if has_pressure:
            score += 30
        if "ABS_TILT_X" in axes and "ABS_TILT_Y" in axes:
            score += 10
        if "BTN_STYLUS" in keys or "BTN_TOOL_RUBBER" in keys:
            score += 10
        name_l = dev.get("name", "").lower()
        if any(h in name_l for h in PEN_NAME_HINTS):
            score += 25
        if any(h in name_l for h in TOUCH_NAME_HINTS):
            score -= 30

        if score > best_score:
            best_score = score
            best = dev
    return best


def select_touch_device(devices: list[dict], pen_path: str = "") -> dict | None:
    best = None
    best_score = -1
    for dev in devices:
        if dev.get("path") == pen_path:
            continue
        axes = dev.get("abs", {})
        if "ABS_MT_POSITION_X" not in axes or "ABS_MT_POSITION_Y" not in axes:
            continue
        score = 20
        if "INPUT_PROP_DIRECT" in dev.get("props", set()):
            score += 20
        name_l = dev.get("name", "").lower()
        if any(h in name_l for h in TOUCH_NAME_HINTS):
            score += 25
        if any(h in name_l for h in PEN_NAME_HINTS):
            score -= 20
        if score > best_score:
            best_score = score
            best = dev
    return best


def compute_active_rect(
    native_w: float,
    native_h: float,
    rotation: int,
    area_scale: float,
    offset_x: float,
    offset_y: float,
    aspect_mode: str,
    target_aspect: float,
) -> tuple[float, float, float, float]:
    swapped = rotation in (90, 270)
    eff_w = native_h if swapped else native_w
    eff_h = native_w if swapped else native_h
    eff_aspect = eff_w / eff_h if eff_h > 0 else 4.0 / 3.0

    box_w = 1.0
    box_h = 1.0
    if aspect_mode == "fit-tablet" and target_aspect > 0:
        if target_aspect > eff_aspect:
            box_h = eff_aspect / target_aspect
        elif target_aspect < eff_aspect:
            box_w = target_aspect / eff_aspect

    scale = clamp(area_scale, 0.25, 1.0)
    box_w = clamp(box_w * scale, 0.05, 1.0)
    box_h = clamp(box_h * scale, 0.05, 1.0)

    cx = clamp(0.5 + offset_x, box_w * 0.5, 1.0 - box_w * 0.5)
    cy = clamp(0.5 + offset_y, box_h * 0.5, 1.0 - box_h * 0.5)
    return (cx - box_w * 0.5, cy - box_h * 0.5, cx + box_w * 0.5, cy + box_h * 0.5)


def rotate_normalized(nx: float, ny: float, rotation: int, flip_x: bool, flip_y: bool) -> tuple[float, float]:
    if rotation == 90:
        u, v = 1.0 - ny, nx
    elif rotation == 180:
        u, v = 1.0 - nx, 1.0 - ny
    elif rotation == 270:
        u, v = ny, 1.0 - nx
    else:
        u, v = nx, ny
    if flip_x:
        u = 1.0 - u
    if flip_y:
        v = 1.0 - v
    return clamp(u, 0.0, 1.0), clamp(v, 0.0, 1.0)


def rotate_tilt(tx: int, ty: int, rotation: int, flip_x: bool, flip_y: bool) -> tuple[int, int]:
    if rotation == 90:
        ox, oy = -ty, tx
    elif rotation == 180:
        ox, oy = -tx, -ty
    elif rotation == 270:
        ox, oy = ty, -tx
    else:
        ox, oy = tx, ty
    if flip_x:
        ox = -ox
    if flip_y:
        oy = -oy
    return ox, oy


def map_active_coords(u: float, v: float, rect: tuple[float, float, float, float]) -> tuple[float, float]:
    u0, v0, u1, v1 = rect
    span_u = max(1e-6, u1 - u0)
    span_v = max(1e-6, v1 - v0)
    return clamp((u - u0) / span_u, 0.0, 1.0), clamp((v - v0) / span_v, 0.0, 1.0)


def apply_pressure_curve(
    raw_val: int,
    max_pressure: int,
    enabled: bool,
    gamma: float,
    p_min: float,
    p_max: float,
    touching: bool = False,
) -> int:
    if max_pressure <= 0:
        return 0
    if not enabled:
        return max_pressure if (touching or raw_val > 0) else 0
    if raw_val <= 0:
        return 0
    p = clamp(raw_val / float(max_pressure), 0.0, 1.0)
    if p <= p_min:
        return 0
    span = max(0.05, p_max - p_min)
    norm = clamp((p - p_min) / span, 0.0, 1.0)
    curved = norm ** clamp(gamma, 0.25, 3.0)
    return int(round(curved * max_pressure))


def emit(payload: dict) -> None:
    try:
        sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        sys.exit(0)


class ConfigLoader:
    def __init__(self, path: str | None) -> None:
        self.path = path
        self.stat_key: tuple[int, int, int] | None = None
        self.config = dict(DEFAULT_CONFIG)
        self.dirty = True
        self.reload(force=True)

    def mark_dirty(self) -> None:
        self.dirty = True

    def reload(self, force: bool = False) -> bool:
        if not self.path:
            self.dirty = False
            return False
        try:
            st = os.stat(self.path)
        except OSError:
            return False
        key = (st.st_mtime_ns, st.st_size, st.st_ino)
        if not force and not self.dirty and key == self.stat_key:
            return False
        try:
            with open(self.path, "r", encoding="utf-8") as fh:
                raw = json.load(fh)
        except (OSError, ValueError):
            return False
        self.stat_key = key
        self.dirty = False
        next_cfg = normalize_config(raw)
        changed = next_cfg != self.config
        self.config = next_cfg
        return changed


def adb_cmd(adb_bin: str, serial: str | None, *args: str) -> list[str]:
    cmd = [adb_bin]
    if serial:
        cmd.extend(["-s", serial])
    cmd.extend(args)
    return cmd


def query_wifi_ip(adb_bin: str, serial: str) -> str:
    try:
        out = subprocess.check_output(
            adb_cmd(adb_bin, serial, "shell", "ip", "-o", "-4", "addr", "show"),
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return parse_wifi_ip(out)


def adb_connect_target(adb_bin: str, addr: str) -> tuple[bool, str]:
    target = addr.strip()
    if not target:
        return False, "Missing IP:port address"
    if ":" not in target:
        target = target + ":5555"
    try:
        out = subprocess.check_output(
            [adb_bin, "connect", target], stderr=subprocess.STDOUT, text=True, timeout=6
        ).strip()
    except (OSError, subprocess.SubprocessError) as exc:
        msg = getattr(exc, "output", "") or str(exc)
        return False, str(msg).strip()
    ok = ("connected to" in out.lower()) and ("failed" not in out.lower()) and ("unable" not in out.lower())
    return ok, out or (f"Connected to {target}" if ok else f"Failed to connect to {target}")


def adb_disconnect_target(adb_bin: str, addr: str) -> tuple[bool, str]:
    cmd = [adb_bin, "disconnect"]
    if addr.strip():
        cmd.append(addr.strip())
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True, timeout=5).strip()
        return True, out or "Disconnected"
    except (OSError, subprocess.SubprocessError) as exc:
        msg = getattr(exc, "output", "") or str(exc)
        return False, str(msg).strip()


def adb_pair_target(adb_bin: str, addr: str, code: str) -> tuple[bool, str]:
    target = addr.strip()
    pin = code.strip()
    if not target or not pin:
        return False, "Provide both IP:port and 6-digit pairing code"
    try:
        out = subprocess.check_output(
            [adb_bin, "pair", target, pin], stderr=subprocess.STDOUT, text=True, timeout=10
        ).strip()
    except (OSError, subprocess.SubprocessError) as exc:
        msg = getattr(exc, "output", "") or str(exc)
        return False, str(msg).strip()
    ok = "successfully paired" in out.lower()
    return ok, out or ("Paired" if ok else "Pairing failed")


def adb_enable_wifi(adb_bin: str, serial: str = "", port: int = 5555) -> dict:
    devices = query_adb_devices(adb_bin)
    usb = None
    if serial:
        usb = next((d for d in devices if d["serial"] == serial and d["state"] == "device"), None)
    if usb is None:
        usb = next((d for d in devices if d["state"] == "device" and not is_wireless_serial(d["serial"])), None)
    if usb is None:
        return {"ok": False, "message": "Plug in the tablet via USB first to enable TCP/IP wireless debugging"}

    ip = query_wifi_ip(adb_bin, usb["serial"])
    if not ip:
        return {"ok": False, "message": "Could not detect tablet Wi-Fi IP — check that Wi-Fi is connected"}

    try:
        subprocess.check_output(
            adb_cmd(adb_bin, usb["serial"], "tcpip", str(port)),
            stderr=subprocess.STDOUT,
            text=True,
            timeout=6,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        msg = getattr(exc, "output", "") or str(exc)
        return {"ok": False, "message": f"adb tcpip {port} failed: {str(msg).strip()}"}

    addr = f"{ip}:{port}"
    time.sleep(1.0)
    ok, msg = adb_connect_target(adb_bin, addr)
    if not ok:
        time.sleep(1.0)
        ok, msg = adb_connect_target(adb_bin, addr)
    return {
        "ok": ok,
        "address": addr,
        "ip": ip,
        "message": f"Wireless ready at {addr} — you can unplug USB now" if ok else msg,
    }


def query_adb_devices(adb_bin: str) -> list[dict]:
    try:
        out = subprocess.check_output(
            [adb_bin, "devices", "-l"], stderr=subprocess.DEVNULL, text=True, timeout=5
        )
    except (OSError, subprocess.SubprocessError):
        return []
    return parse_adb_devices(out)


def find_grab_helper() -> str | None:
    env_path = os.environ.get("PANGU_TABLET_GRAB_AARCH64", "").strip()
    if env_path and os.path.isfile(env_path):
        return env_path
    sibling = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "libexec", "tablet-grab-aarch64")
    if os.path.isfile(sibling):
        return sibling
    return None


def kill_remote_grab_helper(adb_bin: str, serial: str, timeout: float = 2.0) -> None:
    cmd = (
        "pid=$(cat /data/local/tmp/pangu-tablet-grab.pid 2>/dev/null); "
        "[ -n \"$pid\" ] && kill \"$pid\" 2>/dev/null; "
        "pkill -x pangu-tablet-gr 2>/dev/null || true"
    )
    try:
        subprocess.run(
            adb_cmd(adb_bin, serial, "shell", cmd),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def compute_keep_awake_interval(timeout_ms: int) -> float:
    if timeout_ms <= 0:
        return 30.0
    return clamp((timeout_ms / 1000.0) * 0.45, 10.0, 45.0)


def query_screen_timeout_ms(adb_bin: str, serial: str) -> int:
    try:
        out = subprocess.check_output(
            adb_cmd(adb_bin, serial, "shell", "settings", "get", "system", "screen_off_timeout"),
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=3,
        ).strip()
        val = int(out)
        if val > 0:
            return val
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    return 60000


def ensure_grab_helper(adb_bin: str, serial: str, local_path: str) -> str | None:
    remote_path = "/data/local/tmp/pangu-tablet-grab"
    try:
        import hashlib
        with open(local_path, "rb") as fh:
            local_md5 = hashlib.md5(fh.read()).hexdigest()
    except OSError:
        return None
    try:
        out = subprocess.check_output(
            adb_cmd(adb_bin, serial, "shell", f"md5sum {remote_path} 2>/dev/null || true"),
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
        ).strip()
        remote_md5 = out.split()[0] if out else ""
    except (OSError, subprocess.SubprocessError):
        remote_md5 = ""

    if remote_md5 != local_md5:
        kill_remote_grab_helper(adb_bin, serial)
        try:
            subprocess.check_call(
                adb_cmd(adb_bin, serial, "push", local_path, remote_path),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=10,
            )
            subprocess.check_call(
                adb_cmd(adb_bin, serial, "shell", "chmod", "755", remote_path),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
            )
        except (OSError, subprocess.SubprocessError):
            return None
    return remote_path


def query_device_info(adb_bin: str, serial: str) -> tuple[str, str, bool, dict | None, dict | None]:
    model = ""
    try:
        model = subprocess.check_output(
            adb_cmd(adb_bin, serial, "shell", "getprop", "ro.product.model"),
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
        ).strip()
    except (OSError, subprocess.SubprocessError):
        model = ""

    abi = ""
    is_64bit = True
    try:
        abi = subprocess.check_output(
            adb_cmd(adb_bin, serial, "shell", "getprop", "ro.product.cpu.abi"),
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
        ).strip()
        if abi and "64" not in abi:
            is_64bit = False
    except (OSError, subprocess.SubprocessError):
        pass

    try:
        ev_out = subprocess.check_output(
            adb_cmd(adb_bin, serial, "shell", "getevent", "-pl"),
            stderr=subprocess.STDOUT,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return model, abi, is_64bit, None, None

    devices = parse_getevent_devices(ev_out)
    pen = select_pen_device(devices)
    touch = select_touch_device(devices, pen["path"] if pen else "")
    return model, abi, is_64bit, pen, touch


def parse_sensor_orientations(dumpsys_output: str) -> dict[str, int]:
    orientations: dict[str, int] = {}
    current_name = ""
    in_touch_mapper = False
    for raw_line in dumpsys_output.splitlines():
        line = raw_line.strip()
        m_dev = re.match(r"Device\s+\d+:\s+(.+)$", line)
        if m_dev:
            current_name = m_dev.group(1).strip()
            in_touch_mapper = False
            continue
        if line.startswith("Touch Input Mapper"):
            in_touch_mapper = True
            continue
        if in_touch_mapper and current_name and line.startswith("Orientation:"):
            m_rot = re.search(r"Rotation(0|90|180|270)\b", line)
            if m_rot:
                orientations[current_name] = int(m_rot.group(1))
                in_touch_mapper = False
    return orientations


def query_sensor_orientations(adb_bin: str, serial: str) -> dict[str, int]:
    try:
        out = subprocess.check_output(
            adb_cmd(adb_bin, serial, "shell", "dumpsys", "input"),
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return {}
    return parse_sensor_orientations(out)


def resolve_touchpad_rotation(
    cfg_tp_rot: str,
    pen_rot: int,
    orientations: dict[str, int],
    pen: dict | None,
    touch: dict | None,
) -> int:
    if cfg_tp_rot in ("0", "90", "180", "270"):
        return int(cfg_tp_rot)
    base_offset = 0
    pen_name = pen["name"] if pen else ""
    touch_name = touch["name"] if touch else ""
    if pen_name in orientations and touch_name in orientations:
        base_offset = (orientations[touch_name] - orientations[pen_name]) % 360
    elif pen is not None and touch is not None:
        pax = pen["abs"].get("ABS_X")
        pay = pen["abs"].get("ABS_Y")
        tax = touch["abs"].get("ABS_MT_POSITION_X") or touch["abs"].get("ABS_X")
        tay = touch["abs"].get("ABS_MT_POSITION_Y") or touch["abs"].get("ABS_Y")
        if pax and pay and tax and tay:
            pen_land = (pax["max"] - pax["min"]) > (pay["max"] - pay["min"])
            touch_land = (tax["max"] - tax["min"]) > (tay["max"] - tay["min"])
            if pen_land != touch_land:
                base_offset = 90
    return (base_offset + pen_rot) % 360


def build_touchpad_uinput(touch: dict):
    max_slot = int(touch["abs"].get("ABS_MT_SLOT", {}).get("max", 9))
    max_slot = max(4, min(15, max_slot))
    virt_max = 6000
    virt_res = 12  # 500mm x 500mm virtual pad; active travel stays centered at 160mm*speed.

    abs_caps = [
        (e.ABS_X, AbsInfo(value=0, min=0, max=virt_max, fuzz=0, flat=0, resolution=virt_res)),
        (e.ABS_Y, AbsInfo(value=0, min=0, max=virt_max, fuzz=0, flat=0, resolution=virt_res)),
        (e.ABS_MT_SLOT, AbsInfo(value=0, min=0, max=max_slot, fuzz=0, flat=0, resolution=0)),
        (e.ABS_MT_TRACKING_ID, AbsInfo(value=0, min=0, max=65535, fuzz=0, flat=0, resolution=0)),
        (e.ABS_MT_POSITION_X, AbsInfo(value=0, min=0, max=virt_max, fuzz=0, flat=0, resolution=virt_res)),
        (e.ABS_MT_POSITION_Y, AbsInfo(value=0, min=0, max=virt_max, fuzz=0, flat=0, resolution=virt_res)),
    ]
    caps = {
        e.EV_KEY: [
            e.BTN_LEFT,
            e.BTN_TOUCH,
            e.BTN_TOOL_FINGER,
            e.BTN_TOOL_DOUBLETAP,
            e.BTN_TOOL_TRIPLETAP,
            e.BTN_TOOL_QUADTAP,
            e.BTN_TOOL_QUINTTAP,
        ],
        e.EV_ABS: abs_caps,
    }
    ui = UInput(
        caps,
        name="Pangu Android Tablet Touchpad",
        vendor=0x2D1F,
        product=0x060D,
        input_props=[e.INPUT_PROP_POINTER, e.INPUT_PROP_BUTTONPAD],
    )
    return ui, max_slot, virt_max


class TouchpadMapper:
    """Translates raw Android MT Protocol B touchscreen events to a libinput Precision Touchpad."""

    def __init__(self, ui, touch: dict, max_slot: int, virt_max: int) -> None:
        self.ui = ui
        self.max_slot = max_slot
        self.virt_max = virt_max
        ax = touch["abs"].get("ABS_MT_POSITION_X") or touch["abs"].get("ABS_X")
        ay = touch["abs"].get("ABS_MT_POSITION_Y") or touch["abs"].get("ABS_Y")
        self.min_x = ax["min"]
        self.span_x = max(1, ax["max"] - ax["min"])
        self.min_y = ay["min"]
        self.span_y = max(1, ay["max"] - ay["min"])
        init_slot = int(touch["abs"].get("ABS_MT_SLOT", {}).get("value", 0))
        self.cur_slot = max(0, min(self.max_slot, init_slot))
        self.raw_slots: dict[int, dict[str, int]] = {}
        self.last_slot_pos: dict[int, tuple[int, int]] = {}
        self.suppressed_slots: set[int] = set()
        self.emitted_slots: dict[int, tuple[int, int, int]] = {}
        self.emitted_slot_cursor = -1
        self.emitted_touch = False
        self.emitted_tool: int | None = None
        self.next_synth_id = 1
        self.dirty = False
        self.last_fingers: list[dict[str, float]] = []

    def _tool_for_count(self, count: int) -> int | None:
        if count <= 0:
            return None
        if count == 1:
            return e.BTN_TOOL_FINGER
        if count == 2:
            return e.BTN_TOOL_DOUBLETAP
        if count == 3:
            return e.BTN_TOOL_TRIPLETAP
        if count == 4:
            return e.BTN_TOOL_QUADTAP
        return e.BTN_TOOL_QUINTTAP

    def _map_point(self, raw_x: int, raw_y: int, rotation: int, flip_x: bool, flip_y: bool, speed: float) -> tuple[float, float, int, int]:
        nx = clamp((raw_x - self.min_x) / float(self.span_x), 0.0, 1.0)
        ny = clamp((raw_y - self.min_y) / float(self.span_y), 0.0, 1.0)
        ru, rv = rotate_normalized(nx, ny, rotation, flip_x, flip_y)

        raw_aspect = float(self.span_x) / float(self.span_y)
        eff_aspect = (1.0 / raw_aspect) if rotation in (90, 270) else raw_aspect
        base_long = 1920.0
        if eff_aspect >= 1.0:
            w_units = base_long
            h_units = base_long / max(0.25, eff_aspect)
        else:
            h_units = base_long
            w_units = base_long * max(0.25, eff_aspect)

        center = self.virt_max * 0.5
        ox = int(round(clamp(center + (ru - 0.5) * w_units * speed, 0.0, float(self.virt_max))))
        oy = int(round(clamp(center + (rv - 0.5) * h_units * speed, 0.0, float(self.virt_max))))
        return ru, rv, ox, oy

    def _select_slot(self, slot: int) -> None:
        if self.emitted_slot_cursor != slot:
            self.ui.write(e.EV_ABS, e.ABS_MT_SLOT, slot)
            self.emitted_slot_cursor = slot

    def release_all(self) -> bool:
        changed = False
        for slot in sorted(list(self.emitted_slots.keys())):
            self._select_slot(slot)
            self.ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1)
            changed = True
        self.emitted_slots.clear()
        if self.emitted_touch:
            self.ui.write(e.EV_KEY, e.BTN_TOUCH, 0)
            self.emitted_touch = False
            changed = True
        if self.emitted_tool is not None:
            self.ui.write(e.EV_KEY, self.emitted_tool, 0)
            self.emitted_tool = None
            changed = True
        self.last_fingers = []
        if changed:
            self.ui.syn()
        return changed

    def mute_active(self) -> bool:
        for slot in self.raw_slots:
            self.suppressed_slots.add(slot)
        return self.release_all()

    def feed_event(self, ev_type: int, code: int, value: int, muted: bool, rotation: int, flip_x: bool, flip_y: bool, speed: float) -> bool:
        if ev_type == e.EV_ABS:
            if code == e.ABS_MT_SLOT:
                self.cur_slot = max(0, min(self.max_slot, int(value)))
            elif code == e.ABS_MT_TRACKING_ID:
                if value < 0:
                    self.raw_slots.pop(self.cur_slot, None)
                    self.suppressed_slots.discard(self.cur_slot)
                else:
                    last_x, last_y = self.last_slot_pos.get(self.cur_slot, (self.min_x, self.min_y))
                    has_prev = self.cur_slot in self.last_slot_pos
                    self.raw_slots[self.cur_slot] = {
                        "id": int(value) & 0xFFFF,
                        "x": last_x,
                        "y": last_y,
                        "has_pos": 1 if has_prev else 0,
                    }
                    if muted:
                        self.suppressed_slots.add(self.cur_slot)
                    else:
                        # A fresh tracking ID while unmuted must clear any stale palm-suppressed slot.
                        self.suppressed_slots.discard(self.cur_slot)
                self.dirty = True
            elif code == e.ABS_MT_POSITION_X:
                slot_state = self.raw_slots.get(self.cur_slot)
                if slot_state is None:
                    self.next_synth_id = (self.next_synth_id % 65000) + 1
                    _, last_y = self.last_slot_pos.get(self.cur_slot, (self.min_x, self.min_y))
                    slot_state = {"id": self.next_synth_id, "x": int(value), "y": last_y, "has_pos": 1}
                    self.raw_slots[self.cur_slot] = slot_state
                    if muted:
                        self.suppressed_slots.add(self.cur_slot)
                    else:
                        self.suppressed_slots.discard(self.cur_slot)
                else:
                    slot_state["x"] = int(value)
                    slot_state["has_pos"] = 1
                self.last_slot_pos[self.cur_slot] = (slot_state["x"], slot_state["y"])
                self.dirty = True
            elif code == e.ABS_MT_POSITION_Y:
                slot_state = self.raw_slots.get(self.cur_slot)
                if slot_state is None:
                    self.next_synth_id = (self.next_synth_id % 65000) + 1
                    last_x, _ = self.last_slot_pos.get(self.cur_slot, (self.min_x, self.min_y))
                    slot_state = {"id": self.next_synth_id, "x": last_x, "y": int(value), "has_pos": 1}
                    self.raw_slots[self.cur_slot] = slot_state
                    if muted:
                        self.suppressed_slots.add(self.cur_slot)
                    else:
                        self.suppressed_slots.discard(self.cur_slot)
                else:
                    slot_state["y"] = int(value)
                    slot_state["has_pos"] = 1
                self.last_slot_pos[self.cur_slot] = (slot_state["x"], slot_state["y"])
                self.dirty = True
            return False

        if ev_type == e.EV_SYN and code == e.SYN_REPORT:
            if not self.dirty:
                return False
            self.dirty = False
            if muted:
                for slot in self.raw_slots:
                    self.suppressed_slots.add(slot)
                return self.release_all()

            active: dict[int, tuple[int, int, int, float, float]] = {}
            for slot, st in self.raw_slots.items():
                if slot in self.suppressed_slots or not st.get("has_pos"):
                    continue
                ru, rv, ox, oy = self._map_point(st["x"], st["y"], rotation, flip_x, flip_y, speed)
                active[slot] = (st["id"], ox, oy, ru, rv)

            changed = False
            for slot in sorted(list(self.emitted_slots.keys())):
                if slot not in active:
                    self._select_slot(slot)
                    self.ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1)
                    del self.emitted_slots[slot]
                    changed = True

            for slot in sorted(active.keys()):
                tid, ox, oy, _ru, _rv = active[slot]
                prev = self.emitted_slots.get(slot)
                if prev is None or prev[0] != tid:
                    self._select_slot(slot)
                    self.ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, tid)
                    self.ui.write(e.EV_ABS, e.ABS_MT_POSITION_X, ox)
                    self.ui.write(e.EV_ABS, e.ABS_MT_POSITION_Y, oy)
                    self.emitted_slots[slot] = (tid, ox, oy)
                    changed = True
                elif prev[1] != ox or prev[2] != oy:
                    self._select_slot(slot)
                    if prev[1] != ox:
                        self.ui.write(e.EV_ABS, e.ABS_MT_POSITION_X, ox)
                    if prev[2] != oy:
                        self.ui.write(e.EV_ABS, e.ABS_MT_POSITION_Y, oy)
                    self.emitted_slots[slot] = (tid, ox, oy)
                    changed = True

            count = len(active)
            want_touch = count > 0
            if want_touch != self.emitted_touch:
                self.ui.write(e.EV_KEY, e.BTN_TOUCH, 1 if want_touch else 0)
                self.emitted_touch = want_touch
                changed = True

            want_tool = self._tool_for_count(count)
            if want_tool != self.emitted_tool:
                if self.emitted_tool is not None:
                    self.ui.write(e.EV_KEY, self.emitted_tool, 0)
                if want_tool is not None:
                    self.ui.write(e.EV_KEY, want_tool, 1)
                self.emitted_tool = want_tool
                changed = True

            if count > 0:
                first_slot = min(active.keys())
                _tid, fx, fy, _ru, _rv = active[first_slot]
                self.ui.write(e.EV_ABS, e.ABS_X, fx)
                self.ui.write(e.EV_ABS, e.ABS_Y, fy)

            self.last_fingers = [
                {"x": round(active[s][3], 4), "y": round(active[s][4], 4)}
                for s in sorted(active.keys())[:5]
            ]

            if changed:
                self.ui.syn()
            return changed

        return False


def build_uinput(pen: dict, swapped: bool):
    ax = pen["abs"]["ABS_X"]
    ay = pen["abs"]["ABS_Y"]
    span_x = max(1, ax["max"] - ax["min"])
    span_y = max(1, ay["max"] - ay["min"])
    out_max_x = span_y if swapped else span_x
    out_max_y = span_x if swapped else span_y

    # libinput rejects tablets with 0 resolution; fall back to ~100 units/mm.
    res_x = ax["resolution"] if ax["resolution"] > 0 else 100
    res_y = ay["resolution"] if ay["resolution"] > 0 else 100
    if swapped:
        res_x, res_y = res_y, res_x

    max_pressure = pen["abs"].get("ABS_PRESSURE", {}).get("max", 4095)
    if max_pressure <= 0:
        max_pressure = 4095

    abs_caps = [
        (e.ABS_X, AbsInfo(value=0, min=0, max=out_max_x, fuzz=0, flat=0, resolution=res_x)),
        (e.ABS_Y, AbsInfo(value=0, min=0, max=out_max_y, fuzz=0, flat=0, resolution=res_y)),
        (e.ABS_PRESSURE, AbsInfo(value=0, min=0, max=max_pressure, fuzz=0, flat=0, resolution=0)),
    ]

    has_tilt = "ABS_TILT_X" in pen["abs"] and "ABS_TILT_Y" in pen["abs"]
    if has_tilt:
        tx = pen["abs"]["ABS_TILT_X"]
        ty = pen["abs"]["ABS_TILT_Y"]
        abs_caps.append(
            (e.ABS_TILT_X, AbsInfo(value=0, min=tx["min"], max=tx["max"], fuzz=0, flat=0, resolution=tx["resolution"] or 57))
        )
        abs_caps.append(
            (e.ABS_TILT_Y, AbsInfo(value=0, min=ty["min"], max=ty["max"], fuzz=0, flat=0, resolution=ty["resolution"] or 57))
        )

    caps = {
        e.EV_KEY: [
            e.BTN_TOOL_PEN,
            e.BTN_TOOL_RUBBER,
            e.BTN_TOUCH,
            e.BTN_STYLUS,
            e.BTN_STYLUS2,
        ],
        e.EV_ABS: abs_caps,
    }

    ui = UInput(
        caps,
        name="Pangu Android Tablet Pen",
        vendor=0x2D1F,
        product=0x060C,
        input_props=[e.INPUT_PROP_POINTER],
    )
    return ui, out_max_x, out_max_y, max_pressure, has_tilt


def run_bridge(adb_bin: str, loader: ConfigLoader) -> int:
    if UInput is None:
        emit({
            "type": "status",
            "state": "error",
            "transport": "",
            "wifiIp": "",
            "grabActive": False,
            "message": "python-evdev is not installed",
        })
        return 1

    stop_flag = False

    def handle_stop(*_args):
        nonlocal stop_flag
        stop_flag = True

    def handle_hup(*_args):
        loader.mark_dirty()

    signal.signal(signal.SIGINT, handle_stop)
    signal.signal(signal.SIGTERM, handle_stop)
    signal.signal(signal.SIGHUP, handle_hup)

    last_status_key = None
    last_wifi_attempt = 0.0

    def emit_status(payload: dict) -> None:
        nonlocal last_status_key
        key = json.dumps(payload, sort_keys=True)
        if key != last_status_key:
            last_status_key = key
            emit(payload)

    while not stop_flag:
        loader.reload()
        cfg = loader.config
        devices = query_adb_devices(adb_bin)

        has_ready_device = any(d["state"] == "device" for d in devices)
        if (
            not has_ready_device
            and cfg["wirelessAutoConnect"]
            and cfg["wirelessAddress"]
            and (time.monotonic() - last_wifi_attempt) >= 4.0
        ):
            last_wifi_attempt = time.monotonic()
            ok, _msg = adb_connect_target(adb_bin, cfg["wirelessAddress"])
            if ok:
                devices = query_adb_devices(adb_bin)

        if not devices:
            emit_status({
                "type": "status",
                "state": "waiting",
                "transport": "",
                "wifiIp": "",
                "grabActive": False,
                "message": "Waiting for an ADB tablet over USB or wireless debugging",
                "devices": [],
            })
            time.sleep(1.5)
            continue

        chosen = None
        if cfg["deviceSerial"]:
            for d in devices:
                if d["serial"] == cfg["deviceSerial"]:
                    chosen = d
                    break
        else:
            ready_usb = [d for d in devices if d["state"] == "device" and not is_wireless_serial(d["serial"])]
            ready_wifi = [d for d in devices if d["state"] == "device" and is_wireless_serial(d["serial"])]
            if ready_usb:
                chosen = ready_usb[0]
            elif ready_wifi:
                chosen = ready_wifi[0]
            else:
                chosen = devices[0]

        if chosen is None:
            emit_status({
                "type": "status",
                "state": "waiting",
                "transport": "",
                "wifiIp": "",
                "grabActive": False,
                "message": f"Waiting for selected device {cfg['deviceSerial']}",
                "devices": devices,
            })
            time.sleep(1.5)
            continue

        if chosen["state"] == "unauthorized":
            emit_status({
                "type": "status",
                "state": "unauthorized",
                "serial": chosen["serial"],
                "transport": "",
                "wifiIp": "",
                "grabActive": False,
                "model": chosen["model"],
                "message": "Accept the USB debugging prompt on your tablet",
                "devices": devices,
            })
            time.sleep(1.5)
            continue

        if chosen["state"] != "device":
            emit_status({
                "type": "status",
                "state": "waiting",
                "serial": chosen["serial"],
                "transport": "",
                "wifiIp": "",
                "grabActive": False,
                "model": chosen["model"],
                "message": f"Device {chosen['serial']} is {chosen['state']}",
                "devices": devices,
            })
            time.sleep(1.5)
            continue

        serial = chosen["serial"]
        transport = "wifi" if is_wireless_serial(serial) else "usb"
        wifi_ip = serial.split(":", 1)[0] if transport == "wifi" else query_wifi_ip(adb_bin, serial)
        model, abi, is_64bit, pen, touch = query_device_info(adb_bin, serial)
        model = model or chosen["model"] or serial

        # Re-read config after slow ADB probes so mode/suppression toggles clicked mid-reconnect apply immediately.
        loader.reload()
        cfg = loader.config
        input_mode = cfg["inputMode"]
        use_pen = pen is not None and input_mode in ("pen", "hybrid")
        use_touchpad = touch is not None and input_mode in ("hybrid", "touchpad")

        if not use_pen and not use_touchpad:
            err_msg = (
                "No multitouch screen exposed via adb getevent (device may block /dev/input)"
                if input_mode == "touchpad"
                else "No stylus digitizer exposed via adb getevent (device may block /dev/input)"
            )
            emit_status({
                "type": "status",
                "state": "error",
                "serial": serial,
                "transport": "",
                "wifiIp": wifi_ip,
                "grabActive": False,
                "hasTouch": touch is not None,
                "touchpadActive": False,
                "inputMode": input_mode,
                "model": model,
                "message": err_msg,
                "devices": devices,
            })
            time.sleep(3.0)
            continue

        span_x, span_y = 20832, 15624
        min_x, min_y = 0, 0
        out_max_x, out_max_y, max_pressure, has_tilt = 20832, 15624, 4095, False
        swapped = cfg["rotation"] in (90, 270)
        ui = None
        ui_tp = None
        touchpad: TouchpadMapper | None = None

        try:
            if use_pen:
                ax = pen["abs"]["ABS_X"]
                ay = pen["abs"]["ABS_Y"]
                min_x, max_x = ax["min"], ax["max"]
                min_y, max_y = ay["min"], ay["max"]
                span_x = max(1, max_x - min_x)
                span_y = max(1, max_y - min_y)
                ui, out_max_x, out_max_y, max_pressure, has_tilt = build_uinput(pen, swapped)
            elif touch is not None:
                tax = touch["abs"].get("ABS_MT_POSITION_X") or touch["abs"].get("ABS_X")
                tay = touch["abs"].get("ABS_MT_POSITION_Y") or touch["abs"].get("ABS_Y")
                if tax and tay:
                    span_x = max(1, tax["max"] - tax["min"])
                    span_y = max(1, tay["max"] - tay["min"])
            if use_touchpad:
                ui_tp, tp_max_slot, tp_virt_max = build_touchpad_uinput(touch)
                touchpad = TouchpadMapper(ui_tp, touch, tp_max_slot, tp_virt_max)
        except OSError as exc:
            if ui is not None:
                try:
                    ui.close()
                except OSError:
                    pass
            if ui_tp is not None:
                try:
                    ui_tp.close()
                except OSError:
                    pass
            emit_status({
                "type": "status",
                "state": "error",
                "serial": serial,
                "transport": "",
                "wifiIp": wifi_ip,
                "grabActive": False,
                "hasTouch": touch is not None,
                "touchpadActive": False,
                "inputMode": input_mode,
                "model": model,
                "message": f"Cannot open /dev/uinput: {exc}",
                "devices": devices,
            })
            time.sleep(3.0)
            continue

        sensor_orientations = query_sensor_orientations(adb_bin, serial) if use_touchpad else {}

        ev_fmt = "<qqHHi" if is_64bit else "<iiHHi"
        ev_size = struct.calcsize(ev_fmt)

        suppress_pen = cfg["suppressPen"]
        suppress_touch = cfg["suppressTouch"]
        grab_active = False
        helper_used = False
        mux_mode = False
        stream_cmd = adb_cmd(adb_bin, serial, "exec-out", "cat", pen["path"] if use_pen else touch["path"])

        if use_touchpad:
            if abi.startswith("arm64"):
                local_helper = find_grab_helper()
                if local_helper:
                    remote_helper = ensure_grab_helper(adb_bin, serial, local_helper)
                    if remote_helper:
                        pen_arg = pen["path"] if use_pen else "-"
                        grab_pen_arg = "1" if (use_pen and suppress_pen) else "0"
                        touch_arg = touch["path"]
                        grab_touch_arg = "1" if suppress_touch else "0"
                        stream_cmd = adb_cmd(
                            adb_bin, serial, "exec-out",
                            remote_helper, "--mux", pen_arg, grab_pen_arg, touch_arg, grab_touch_arg,
                        )
                        mux_mode = True
                        helper_used = True
                        grab_active = (use_pen and suppress_pen) or suppress_touch
            elif use_pen:
                # Non-arm64 fallback without mux helper: fall back to pen-only stream.
                use_touchpad = False
                if ui_tp is not None:
                    try:
                        ui_tp.close()
                    except OSError:
                        pass
                ui_tp = None
                touchpad = None
        else:
            want_grab = suppress_pen or (suppress_touch and touch is not None)
            if want_grab and abi.startswith("arm64"):
                local_helper = find_grab_helper()
                if local_helper:
                    remote_helper = ensure_grab_helper(adb_bin, serial, local_helper)
                    if remote_helper:
                        args = [remote_helper, pen["path"], "1" if suppress_pen else "0"]
                        if suppress_touch and touch is not None:
                            args.append(touch["path"])
                        stream_cmd = adb_cmd(adb_bin, serial, "exec-out", *args)
                        grab_active = True
                        helper_used = True

        if not helper_used:
            kill_remote_grab_helper(adb_bin, serial)

        keep_awake_interval = compute_keep_awake_interval(query_screen_timeout_ms(adb_bin, serial))
        last_keep_awake = 0.0
        keepawake_proc: subprocess.Popen | None = None

        proc = subprocess.Popen(
            stream_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0,
        )

        emit_status({
            "type": "status",
            "state": "connected",
            "serial": serial,
            "transport": transport,
            "wifiIp": wifi_ip,
            "model": model,
            "device": pen["name"] if pen else (touch["name"] if touch else ""),
            "eventPath": pen["path"] if pen else (touch["path"] if touch else ""),
            "touchDevice": touch["name"] if touch else "",
            "hasTouch": touch is not None,
            "touchpadActive": use_touchpad,
            "inputMode": input_mode,
            "grabActive": grab_active,
            "maxX": span_x,
            "maxY": span_y,
            "maxPressure": max_pressure,
            "hasTilt": has_tilt,
            "devices": devices,
            "message": f"Connected to {model}",
        })

        stream = proc.stdout
        assert stream is not None
        fd = stream.fileno()

        has_pressure_axis = bool(use_pen and pen is not None and "ABS_PRESSURE" in pen["abs"])
        has_native_prox = bool(
            use_pen
            and pen is not None
            and any(k in pen["keys"] for k in ("BTN_TOOL_PEN", "BTN_TOOL_BRUSH", "BTN_TOOL_RUBBER", "BTN_TOOL_PENCIL", "BTN_TOOL_AIRBRUSH"))
        )
        raw_x = pen["abs"]["ABS_X"]["value"] if use_pen and pen is not None else 0
        raw_y = pen["abs"]["ABS_Y"]["value"] if use_pen and pen is not None else 0
        raw_pressure = 0
        raw_tilt_x = 0
        raw_tilt_y = 0
        touching = False
        emitted_touch = False
        in_prox = False
        pen_last_prox = 0.0
        active_tool = e.BTN_TOOL_PEN
        smooth_u = None
        smooth_v = None
        dirty_frame = False
        saw_pos = False
        left_prox = False
        last_telemetry = 0.0
        last_touch_telemetry = 0.0
        last_cfg_poll = time.monotonic()
        buf = bytearray()
        frame_size = (1 + ev_size) if mux_mode else ev_size

        def release_pen() -> None:
            nonlocal emitted_touch, in_prox
            if ui is None:
                return
            changed = False
            if emitted_touch:
                ui.write(e.EV_KEY, e.BTN_TOUCH, 0)
                ui.write(e.EV_ABS, e.ABS_PRESSURE, 0)
                emitted_touch = False
                changed = True
            if in_prox:
                ui.write(e.EV_KEY, active_tool, 0)
                in_prox = False
                changed = True
            if changed:
                ui.syn()

        try:
            while not stop_flag:
                ready, _, _ = select.select([fd], [], [], 0.15)
                now = time.monotonic()
                if loader.dirty or (now - last_cfg_poll) >= 0.15:
                    last_cfg_poll = now
                    if loader.reload():
                        cfg = loader.config
                        if cfg["deviceSerial"] and cfg["deviceSerial"] != serial:
                            break
                        if (
                            cfg["inputMode"] != input_mode
                            or cfg["suppressPen"] != suppress_pen
                            or cfg["suppressTouch"] != suppress_touch
                        ):
                            break
                        if use_pen and pen is not None and ui is not None:
                            next_swapped = cfg["rotation"] in (90, 270)
                            if next_swapped != swapped:
                                release_pen()
                                ui.close()
                                swapped = next_swapped
                                try:
                                    ui, out_max_x, out_max_y, max_pressure, has_tilt = build_uinput(pen, swapped)
                                except OSError:
                                    ui = None
                                    break
                        smooth_u = None
                        smooth_v = None

                if keepawake_proc is not None and keepawake_proc.poll() is not None:
                    keepawake_proc = None
                if cfg["keepAwake"] and keepawake_proc is None and (now - last_keep_awake) >= keep_awake_interval:
                    last_keep_awake = now
                    try:
                        # KEYCODE_UNKNOWN (0) resets Android's user-activity timeout without UI side effects.
                        keepawake_proc = subprocess.Popen(
                            adb_cmd(adb_bin, serial, "shell", "input", "keyevent", "0"),
                            stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                        )
                    except OSError:
                        keepawake_proc = None

                if not ready:
                    if proc.poll() is not None:
                        break
                    continue

                chunk = os.read(fd, frame_size * 32)
                if not chunk:
                    break
                buf.extend(chunk)

                rect = (
                    compute_active_rect(
                        span_x,
                        span_y,
                        cfg["rotation"],
                        cfg["areaScale"],
                        cfg["areaOffsetX"],
                        cfg["areaOffsetY"],
                        cfg["aspectMode"],
                        cfg["targetAspect"],
                    )
                    if use_pen
                    else (0.0, 0.0, 1.0, 1.0)
                )
                tp_rot = (
                    resolve_touchpad_rotation(
                        cfg["touchpadRotation"], cfg["rotation"], sensor_orientations, pen, touch
                    )
                    if touchpad is not None
                    else 0
                )

                while len(buf) >= frame_size:
                    if mux_mode:
                        tag = buf[0]
                        _sec, _usec, ev_type, code, value = struct.unpack_from(ev_fmt, buf, 1)
                    else:
                        tag = 0 if use_pen else 1
                        _sec, _usec, ev_type, code, value = struct.unpack_from(ev_fmt, buf, 0)
                    del buf[:frame_size]

                    if tag == 255:
                        continue

                    if tag == 1:
                        if touchpad is None:
                            continue
                        t_now = time.monotonic()
                        palm_s = cfg["touchpadPalmRejectMs"] / 1000.0
                        pen_elapsed = t_now - pen_last_prox
                        muted = use_pen and (
                            (in_prox and pen_elapsed < max(0.6, palm_s)) or pen_elapsed < palm_s
                        )
                        syn_emitted = touchpad.feed_event(
                            ev_type,
                            code,
                            value,
                            muted,
                            tp_rot,
                            cfg["flipX"],
                            cfg["flipY"],
                            cfg["touchpadSpeed"],
                        )
                        if syn_emitted and cfg["telemetry"]:
                            if (t_now - last_touch_telemetry) >= 0.033 or not touchpad.last_fingers:
                                last_touch_telemetry = t_now
                                emit({"type": "touch", "fingers": touchpad.last_fingers})
                        continue

                    if not use_pen or ui is None:
                        continue

                    if ev_type == e.EV_KEY:
                        if code in (e.BTN_TOOL_BRUSH, e.BTN_TOOL_PENCIL, e.BTN_TOOL_AIRBRUSH):
                            code = e.BTN_TOOL_PEN
                        elif code == e.BTN_TOOL_RUBBER and not cfg["eraserEnabled"]:
                            code = e.BTN_TOOL_PEN
                        elif cfg["swapStylusButtons"]:
                            if code == e.BTN_STYLUS:
                                code = e.BTN_STYLUS2
                            elif code == e.BTN_STYLUS2:
                                code = e.BTN_STYLUS

                        if code in (e.BTN_TOOL_PEN, e.BTN_TOOL_RUBBER):
                            in_prox = bool(value)
                            pen_last_prox = time.monotonic()
                            if in_prox:
                                active_tool = code
                                left_prox = False
                                if touchpad is not None:
                                    touchpad.mute_active()
                            else:
                                left_prox = True
                                smooth_u = None
                                smooth_v = None
                                raw_pressure = 0
                                touching = False
                            ui.write(e.EV_KEY, code, value)
                            dirty_frame = True
                        elif code == e.BTN_TOUCH:
                            touching = bool(value)
                            if not touching:
                                raw_pressure = 0
                            dirty_frame = True
                        elif code in (e.BTN_STYLUS, e.BTN_STYLUS2):
                            ui.write(e.EV_KEY, code, value)
                            dirty_frame = True

                    elif ev_type == e.EV_ABS:
                        if code == e.ABS_X:
                            raw_x = value
                            saw_pos = True
                            dirty_frame = True
                        elif code == e.ABS_Y:
                            raw_y = value
                            saw_pos = True
                            dirty_frame = True
                        elif code == e.ABS_PRESSURE:
                            raw_pressure = value
                            dirty_frame = True
                        elif code == e.ABS_TILT_X:
                            raw_tilt_x = value
                            dirty_frame = True
                        elif code == e.ABS_TILT_Y:
                            raw_tilt_y = value
                            dirty_frame = True

                    elif ev_type == e.EV_SYN and code == e.SYN_REPORT:
                        if not dirty_frame:
                            continue
                        dirty_frame = False

                        if not has_native_prox and not in_prox and not left_prox and (saw_pos or touching or raw_pressure > 0):
                            in_prox = True
                            pen_last_prox = time.monotonic()
                            ui.write(e.EV_KEY, active_tool, 1)
                            if touchpad is not None:
                                touchpad.mute_active()
                        elif in_prox:
                            pen_last_prox = time.monotonic()
                        saw_pos = False
                        left_prox = False

                        nx = clamp((raw_x - min_x) / float(span_x), 0.0, 1.0)
                        ny = clamp((raw_y - min_y) / float(span_y), 0.0, 1.0)
                        ru, rv = rotate_normalized(nx, ny, cfg["rotation"], cfg["flipX"], cfg["flipY"])
                        mu, mv = map_active_coords(ru, rv, rect)

                        smoothing = cfg["smoothing"]
                        if smoothing > 0:
                            alpha = 1.0 / (1.0 + smoothing * 0.65)
                            if smooth_u is None:
                                smooth_u, smooth_v = mu, mv
                            else:
                                smooth_u += (mu - smooth_u) * alpha
                                smooth_v += (mv - smooth_v) * alpha
                            out_u, out_v = smooth_u, smooth_v
                        else:
                            out_u, out_v = mu, mv

                        ui.write(e.EV_ABS, e.ABS_X, int(round(out_u * out_max_x)))
                        ui.write(e.EV_ABS, e.ABS_Y, int(round(out_v * out_max_y)))

                        mapped_p = apply_pressure_curve(
                            raw_pressure,
                            max_pressure,
                            cfg["pressureEnabled"],
                            cfg["pressureGamma"],
                            cfg["pressureMin"],
                            cfg["pressureMax"],
                            touching=touching,
                        )
                        if has_pressure_axis and cfg["pressureEnabled"] and cfg["pressureMin"] > 0.0:
                            effective_touch = touching and mapped_p > 0
                        else:
                            effective_touch = touching
                        if effective_touch != emitted_touch:
                            emitted_touch = effective_touch
                            ui.write(e.EV_KEY, e.BTN_TOUCH, 1 if emitted_touch else 0)
                        ui.write(e.EV_ABS, e.ABS_PRESSURE, mapped_p if emitted_touch else 0)

                        if has_tilt:
                            if cfg["tiltEnabled"]:
                                otx, oty = rotate_tilt(
                                    raw_tilt_x, raw_tilt_y, cfg["rotation"], cfg["flipX"], cfg["flipY"]
                                )
                                ui.write(e.EV_ABS, e.ABS_TILT_X, otx)
                                ui.write(e.EV_ABS, e.ABS_TILT_Y, oty)
                            else:
                                ui.write(e.EV_ABS, e.ABS_TILT_X, 0)
                                ui.write(e.EV_ABS, e.ABS_TILT_Y, 0)

                        ui.syn()

                        if cfg["telemetry"]:
                            t_now = time.monotonic()
                            if (t_now - last_telemetry) >= 0.033 or not in_prox:
                                last_telemetry = t_now
                                emit({
                                    "type": "pen",
                                    "inProx": in_prox,
                                    "touching": emitted_touch,
                                    "x": round(out_u, 4),
                                    "y": round(out_v, 4),
                                    "rawX": round(ru, 4),
                                    "rawY": round(rv, 4),
                                    "pressure": round((mapped_p if emitted_touch else 0) / float(max_pressure), 4),
                                    "rawPressure": round(clamp(raw_pressure / float(max_pressure), 0.0, 1.0), 4),
                                    "tiltX": raw_tilt_x,
                                    "tiltY": raw_tilt_y,
                                })
        finally:
            try:
                release_pen()
            except OSError:
                pass
            if touchpad is not None:
                try:
                    touchpad.release_all()
                except OSError:
                    pass
            if keepawake_proc is not None:
                try:
                    keepawake_proc.terminate()
                    keepawake_proc.wait(timeout=0.5)
                except (OSError, subprocess.SubprocessError):
                    try:
                        keepawake_proc.kill()
                    except OSError:
                        pass
            try:
                proc.terminate()
                proc.wait(timeout=1.0)
            except (OSError, subprocess.SubprocessError):
                try:
                    proc.kill()
                except OSError:
                    pass
            if helper_used:
                kill_remote_grab_helper(adb_bin, serial, timeout=1.5)
            if ui is not None:
                try:
                    ui.close()
                except OSError:
                    pass
            if ui_tp is not None:
                try:
                    ui_tp.close()
                except OSError:
                    pass

        if not stop_flag:
            time.sleep(0.6)

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Bridge an ADB Android stylus tablet to Linux uinput")
    parser.add_argument("--config", help="Path to runtime JSON config file")
    parser.add_argument("--adb", default=os.environ.get("ADB", "adb"), help="Path to adb executable")
    parser.add_argument("--probe", action="store_true", help="Print connected ADB devices and exit")
    parser.add_argument("--enable-wifi", nargs="?", const="", default=None, metavar="SERIAL", help="Switch a USB-connected tablet to ADB over Wi-Fi (TCP 5555)")
    parser.add_argument("--connect", metavar="IP:PORT", help="Connect to an ADB wireless device")
    parser.add_argument("--disconnect", nargs="?", const="", default=None, metavar="IP:PORT", help="Disconnect an ADB wireless device")
    parser.add_argument("--pair", nargs=2, metavar=("IP:PORT", "CODE"), help="Pair with Android Wireless Debugging")
    args = parser.parse_args()

    if args.probe:
        devices = query_adb_devices(args.adb)
        emit({"type": "probe", "devices": devices})
        return 0
    if args.enable_wifi is not None:
        res = adb_enable_wifi(args.adb, args.enable_wifi)
        emit({"type": "wireless", **res})
        return 0 if res.get("ok") else 1
    if args.connect:
        ok, msg = adb_connect_target(args.adb, args.connect)
        target = args.connect.strip()
        if ":" not in target:
            target += ":5555"
        emit({"type": "wireless", "ok": ok, "address": target, "message": msg})
        return 0 if ok else 1
    if args.disconnect is not None:
        ok, msg = adb_disconnect_target(args.adb, args.disconnect)
        emit({"type": "wireless", "ok": ok, "message": msg})
        return 0 if ok else 1
    if args.pair:
        ok, msg = adb_pair_target(args.adb, args.pair[0], args.pair[1])
        emit({"type": "wireless", "ok": ok, "message": msg})
        return 0 if ok else 1

    loader = ConfigLoader(args.config)
    return run_bridge(args.adb, loader)


if __name__ == "__main__":
    sys.exit(main())
