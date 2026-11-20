#!/usr/bin/env python3

import colorsys
import os
import shutil
import subprocess
import sys
from pathlib import Path


def cmd(*args, input=None):
    return subprocess.check_output(args, input=input)


def parse_ppm_pixel(raw: bytes):
    idx = 0
    tokens = []
    n = len(raw)
    while len(tokens) < 4 and idx < n:
        while idx < n and raw[idx] in b" \t\r\n":
            idx += 1
        if idx < n and raw[idx] == ord("#"):
            while idx < n and raw[idx] != ord("\n"):
                idx += 1
            continue
        start = idx
        while idx < n and raw[idx] not in b" \t\r\n#":
            idx += 1
        if start < idx:
            tokens.append(raw[start:idx])
    if len(tokens) < 4 or tokens[0] != b"P6":
        raise ValueError("Invalid PPM header")
    idx += 1  # single whitespace byte after maxval
    if idx + 3 > n:
        raise ValueError("Truncated PPM pixel data")
    return raw[idx], raw[idx + 1], raw[idx + 2]


def main():
    for dep in ("grim", "slurp", "magick", "wl-copy", "notify-send"):
        if shutil.which(dep) is None:
            print(f"Color picker missing dependency: {dep}", file=sys.stderr)
            if shutil.which("notify-send"):
                subprocess.call(
                    [
                        "notify-send",
                        "Color Picker",
                        f"Missing dependency: {dep}",
                        "-u",
                        "critical",
                    ]
                )
            sys.exit(1)

    selection = subprocess.run(["slurp", "-p"], capture_output=True, text=True)
    coords = selection.stdout.strip()
    if selection.returncode != 0 or not coords:
        sys.exit(0)

    pixels = cmd("grim", "-g", coords, "-t", "ppm", "-")
    r, g, b = parse_ppm_pixel(pixels)

    hex_color = f"#{r:02X}{g:02X}{b:02X}"
    rgb_color = f"rgb({r}, {g}, {b})"

    rn, gn, bn = r / 255, g / 255, b / 255
    h, s, v = colorsys.rgb_to_hsv(rn, gn, bn)
    hsv_color = f"hsv({round(h*360)}, {round(s*100)}%, {round(v*100)}%)"

    runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "pangu"
    runtime_dir.mkdir(parents=True, exist_ok=True)
    icon = runtime_dir / "colorpicker-swatch.png"
    cmd("magick", "-size", "64x64", f"xc:{hex_color}", str(icon))

    subprocess.run(["wl-copy"], input=hex_color.encode(), check=True)

    proc = subprocess.Popen(
        [
            "notify-send",
            "Color Picked",
            f"{hex_color} copied to clipboard",
            "-i",
            str(icon),
            "-a",
            "ColorPicker",
            "-u",
            "normal",
            "--action=hex=Copy HEX",
            "--action=rgb=Copy RGB",
            "--action=hsv=Copy HSV",
        ],
        stdout=subprocess.PIPE,
    )

    action = proc.communicate()[0].decode().strip()

    if action == "rgb":
        subprocess.run(["wl-copy"], input=rgb_color.encode(), check=True)
        subprocess.call(
            [
                "notify-send",
                "Color Picker",
                f"RGB copied: {rgb_color}",
                "-i",
                str(icon),
                "-u",
                "low",
            ]
        )
    elif action == "hsv":
        subprocess.run(["wl-copy"], input=hsv_color.encode(), check=True)
        subprocess.call(
            [
                "notify-send",
                "Color Picker",
                f"HSV copied: {hsv_color}",
                "-i",
                str(icon),
                "-u",
                "low",
            ]
        )
    elif action == "hex":
        subprocess.run(["wl-copy"], input=hex_color.encode(), check=True)
        subprocess.call(
            [
                "notify-send",
                "Color Picker",
                f"HEX copied: {hex_color}",
                "-i",
                str(icon),
                "-u",
                "low",
            ]
        )


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"Color picker failed: {error}", file=sys.stderr)
        if shutil.which("notify-send"):
            subprocess.run(["notify-send", "Color Picker", "Could not capture or copy the color", "-u", "critical"])
        sys.exit(1)
