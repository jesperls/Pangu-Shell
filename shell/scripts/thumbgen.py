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
from wallpaper_files import discover, scan, VIDEO_EXTENSIONS, IMAGE_EXTENSIONS


def media_files(root):
    yield from (Path(path) for path in discover(root)['files'])


def generate(source, destination):
    if current(source, destination):
        return True
    try:
        if source.suffix.lower() in IMAGE_EXTENSIONS:
            command = ['magick', '-limit', 'thread', '1', str(source) + '[0]',
                       '-auto-orient', '-resize', '320x200^', '-gravity', 'center',
                       '-extent', '320x200', '-quality', '85']
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
    parser.add_argument('--directory')
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text())
    directory = args.directory or config.get('wallPath') or args.fallback
    if not directory:
        raise ValueError('Wallpaper directory is not configured')
    result = scan(directory, None if args.directory else args.fallback)
    root = Path(result['root'])
    namespace = hashlib.md5((str(root).rstrip('/') or '/').encode()).hexdigest()
    cache = Path(args.cache) / 'thumbnails' / namespace
    files = [Path(path) for path in result['files']]
    def render(source):
        destination = cache / (str(source.relative_to(root)) + '.preview.jpg')
        return generate(source, destination)
    with ThreadPoolExecutor(max_workers=min(4, os.cpu_count() or 1)) as executor:
        results = list(executor.map(render, files))
    print(f'Thumbnails ready: {sum(results)}/{len(results)}')
    # A single unreadable file must not suppress the thumbnails that did render.
    return 0 if not files or any(results) else 1


if __name__ == '__main__':
    sys.exit(main())
