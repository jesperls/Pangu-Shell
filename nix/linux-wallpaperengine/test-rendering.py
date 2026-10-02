import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


with tempfile.TemporaryDirectory(prefix="pangu-web-properties-") as directory:
    root = Path(directory)
    (root / "assets").mkdir()
    (root / "runtime").mkdir(mode=0o700)
    (root / "project.json").write_text(json.dumps({
        "title": "Pangu web property regression", "type": "web", "file": "index.html",
        "general": {"properties": {
            "paused": {"type": "bool", "value": False},
            "speed": {"type": "slider", "value": 5, "min": 1, "max": 10},
            "bgcolor": {"type": "color", "value": "0 1 0"},
            "mode": {"type": "combo", "value": 1, "options": [{"value": 1, "label": "First"}, {"value": 2, "label": "Second"}]},
            "caption": {"type": "textinput", "value": "default"},
        }},
    }))
    (root / "index.html").write_text('''<!doctype html><html><head>
<style>html,body{margin:0;width:100%;height:100%;background:blue}</style>
</head><body><script>
setTimeout(function () {
    window.wallpaperPropertyListener = {
        applyUserProperties: function (p) {
            const defaults = p.paused.value === false && p.speed.value === 5 && p.mode.value === 1 && p.caption.value === 'default';
            const overrides = p.paused.value === true && p.speed.value === 1 && p.mode.value === 2 && p.caption.value === 'changed';
            if (defaults || overrides) {
                const channels = p.bgcolor.value.split(' ').map(c => Math.round(Number(c) * 255));
                document.documentElement.style.background = 'rgb(' + channels.join(',') + ')';
                document.body.style.background = 'rgb(' + channels.join(',') + ')';
            }
        }
    };
}, 500);
</script></body></html>''')
    env = dict(os.environ, XDG_SESSION_TYPE="x11", SDL_AUDIODRIVER="dummy",
               XDG_RUNTIME_DIR=str(root / "runtime"), XDG_CACHE_HOME=str(root / "cache"),
               XDG_CONFIG_HOME=str(root / "config"), LIBGL_ALWAYS_SOFTWARE="1",
               __GLX_VENDOR_LIBRARY_NAME="mesa", GALLIUM_DRIVER="llvmpipe")
    env.pop("WAYLAND_DISPLAY", None)
    for name, args, expected in [
        ("defaults", [], "#00FF00"),
        ("overrides", ["--set-property", "paused=1", "--set-property", "speed=1",
                       "--set-property", "bgcolor=1 0 0", "--set-property", "mode=2",
                       "--set-property", "caption=changed"], "#FF0000"),
    ]:
        logfile = root / (name + ".log")
        with logfile.open("w") as output:
            command = [sys.argv[1], "--window", "0x0x160x120", "--silent", "--noautomute",
                       "--use-gl=angle", "--use-angle=gl", "--ozone-platform=x11",
                       "--no-audio-processing", "--no-fullscreen-pause", "--fps", "30",
                       "--assets-dir", str(root / "assets"), *args, str(root)]
            process = subprocess.Popen(command, env=env, stdout=output, stderr=output, start_new_session=True)
            try:
                deadline = time.monotonic() + 15
                pixel = ""
                while time.monotonic() < deadline and process.poll() is None:
                    time.sleep(0.2)
                    capture = subprocess.run(["magick", "import", "-window", "root", "-crop",
                                              "1x1+80+60", "-depth", "8", "txt:-"],
                                             env=env, capture_output=True, text=True, timeout=3, check=True)
                    pixel = capture.stdout
                    if expected in pixel:
                        break
                if expected not in pixel:
                    raise AssertionError(name + " pixel: " + pixel + "\n" + logfile.read_text())
                print(name + " rendered " + expected, flush=True)
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
