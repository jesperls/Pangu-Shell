import os
from pathlib import Path
import subprocess
import tempfile


def render_atomic(command, destination, timeout):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.', suffix=destination.suffix, dir=destination.parent)
    os.close(fd)
    temporary = Path(name)
    try:
        result = subprocess.run([*command, str(temporary)], capture_output=True, text=True,
                                errors='replace', timeout=timeout)
        if result.returncode != 0 or temporary.stat().st_size == 0:
            raise RuntimeError(result.stderr.strip() or 'Renderer produced no image')
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def current(source, destination):
    try:
        return destination.stat().st_size > 0 and destination.stat().st_mtime_ns >= source.stat().st_mtime_ns
    except OSError:
        return False


def frame_command(source, thumbnail=False, seek=None):
    command = ['ffmpeg', '-nostdin', '-loglevel', 'error', '-y', '-threads', '1']
    if seek is not None:
        command += ['-ss', str(seek)]
    command += ['-i', str(source), '-frames:v', '1', '-threads', '1', '-filter_threads', '1']
    if thumbnail:
        command += ['-vf', 'scale=140:140:force_original_aspect_ratio=increase,crop=140:140']
    return command + ['-q:v', '2', '-f', 'image2']
