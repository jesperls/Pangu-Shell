#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path

VIDEO_EXTENSIONS = {'.mp4', '.webm', '.mov', '.avi', '.mkv'}
IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp', '.tif', '.tiff', '.bmp'}
MEDIA_EXTENSIONS = VIDEO_EXTENSIONS | IMAGE_EXTENSIONS | {'.gif'}


def discover(directory):
    root = Path(os.path.abspath(os.path.expanduser(str(directory))))
    if not root.is_dir():
        raise ValueError(f'Wallpaper directory does not exist: {root}')
    files, directories = [], []

    def visit(folder, ancestors):
        try:
            info = folder.stat()
            identity = (info.st_dev, info.st_ino)
            if identity in ancestors:
                return
            with os.scandir(folder) as entries:
                children = sorted(entries, key=lambda entry: entry.name)
        except OSError:
            return
        for entry in children:
            if entry.name.startswith('.'):
                continue
            path = folder / entry.name
            try:
                if entry.is_dir():
                    # Keep alias paths for saved selections; only ancestor identities break cycles.
                    target = entry.stat()
                    if (target.st_dev, target.st_ino) in ancestors | {identity}:
                        continue
                    directories.append(str(path))
                    visit(path, ancestors | {identity})
                elif entry.is_file() and path.suffix.lower() in MEDIA_EXTENSIONS:
                    files.append(str(path))
            except OSError:
                continue

    visit(root, set())
    return {'root': str(root), 'files': sorted(files), 'directories': sorted(directories)}


def scan(directory, fallback=None):
    try:
        result = discover(directory)
    except ValueError:
        if not fallback:
            raise
        result = {'root': os.path.abspath(os.path.expanduser(directory)), 'files': [], 'directories': []}
    result['fallback'] = False
    if not result['files'] and fallback:
        fallback_root = os.path.abspath(os.path.expanduser(fallback))
        if fallback_root != result['root']:
            try:
                alternative = discover(fallback_root)
                if alternative['files']:
                    result = dict(alternative, fallback=True)
            except ValueError:
                pass
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    parser.add_argument('--fallback')
    args = parser.parse_args()
    print(json.dumps(scan(args.directory, args.fallback), ensure_ascii=False))


if __name__ == '__main__':
    main()
