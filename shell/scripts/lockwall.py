#!/usr/bin/env python3
import argparse
import hashlib
from pathlib import Path
import subprocess
import sys

from media_cache import current, frame_command, render_atomic


def generate(source_path, cache):
    source = Path(source_path).expanduser()
    if source.suffix.lower() not in {'.mp4', '.webm', '.mov', '.avi', '.mkv', '.gif'}:
        return
    destination = Path(cache) / 'lockscreen' / (hashlib.md5(source_path.encode()).hexdigest() + '.jpg')
    if not current(source, destination):
        render_atomic(frame_command(source), destination, 30)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('wallpaper')
    parser.add_argument('cache')
    args = parser.parse_args()
    try:
        generate(args.wallpaper, args.cache)
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'lockscreen wallpaper: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
