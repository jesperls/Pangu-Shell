#!/usr/bin/env python3
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import sys
import subprocess

from media_cache import current, frame_command, render_atomic

VIDEO_EXTENSIONS = {'.mp4', '.webm', '.mov', '.avi', '.mkv'}
IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp', '.tif', '.tiff', '.bmp'}
MEDIA_EXTENSIONS = VIDEO_EXTENSIONS | IMAGE_EXTENSIONS | {'.gif'}


def media_files(root):
    for directory, folders, files in os.walk(root):
        folders[:] = sorted(folder for folder in folders if not folder.startswith('.'))
        for name in sorted(files):
            path = Path(directory) / name
            if not name.startswith('.') and path.suffix.lower() in MEDIA_EXTENSIONS:
                yield path


def generate(source, destination):
    if current(source, destination):
        return True
    try:
        if source.suffix.lower() in IMAGE_EXTENSIONS:
            command = ['magick', '-limit', 'thread', '1', str(source) + '[0]',
                       '-auto-orient', '-resize', '140x140^', '-gravity', 'center',
                       '-extent', '140x140', '-quality', '85']
            render_atomic(command, destination, 15)
        elif source.suffix.lower() in VIDEO_EXTENSIONS:
            try:
                render_atomic(frame_command(source, thumbnail=True, seek=1), destination, 30)
            except RuntimeError:
                render_atomic(frame_command(source, thumbnail=True), destination, 30)
        else:
            render_atomic(frame_command(source, thumbnail=True), destination, 15)
        return True
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'{source}: {error}', file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('config')
    parser.add_argument('cache')
    parser.add_argument('fallback', nargs='?')
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text())
    directory = config.get('wallPath') or args.fallback
    if not directory:
        raise ValueError('Wallpaper directory is not configured')
    root = Path(directory).expanduser()
    if not root.is_dir():
        raise ValueError(f'Wallpaper directory does not exist: {root}')
    namespace = hashlib.md5((directory.rstrip('/') or '/').encode()).hexdigest()
    cache = Path(args.cache) / 'thumbnails' / namespace
    files = list(media_files(root))
    def render(source):
        destination = cache / (str(source.relative_to(root)) + '.jpg')
        return generate(source, destination)
    with ThreadPoolExecutor(max_workers=min(4, os.cpu_count() or 1)) as executor:
        results = list(executor.map(render, files))
    print(f'Thumbnails ready: {sum(results)}/{len(results)}')
    # A single unreadable file must not suppress the thumbnails that did render.
    return 0 if not files or any(results) else 1


if __name__ == '__main__':
    sys.exit(main())
