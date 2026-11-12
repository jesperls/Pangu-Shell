#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def generate(image, template, base_config, scheme, mode, destination):
    dest = Path(destination)
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd_out, tmp_out = tempfile.mkstemp(prefix=dest.name + ".", dir=dest.parent)
    os.close(fd_out)
    fd_cfg, tmp_cfg = tempfile.mkstemp(prefix="matugen-", suffix=".toml", dir=dest.parent)
    os.close(fd_cfg)
    try:
        lines = []
        for line in Path(base_config).read_text().splitlines():
            if line.startswith("input_path ="):
                lines.append(f"input_path = {json.dumps(str(Path(template).resolve()))}")
            elif line.startswith("output_path ="):
                lines.append(f"output_path = {json.dumps(tmp_out)}")
            else:
                lines.append(line)
        Path(tmp_cfg).write_text("\n".join(lines) + "\n")
        subprocess.run(
            ["matugen", "image", image, "--source-color-index", "0", "-c", tmp_cfg, "-t", scheme, "-m", mode],
            check=True,
        )
        os.replace(tmp_out, dest)
    finally:
        for path in (tmp_out, tmp_cfg):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def main():
    if len(sys.argv) != 7:
        print("usage: matugen_palette.py <image> <template> <config> <scheme> <mode> <destination>", file=sys.stderr)
        return 1
    generate(*sys.argv[1:7])
    return 0


if __name__ == "__main__":
    sys.exit(main())
