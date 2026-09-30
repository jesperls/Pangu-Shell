import json
import pathlib
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    config = root / "config with 'quotes' and $dollars"
    config.mkdir()
    target = config / "system.json"
    target.write_text(json.dumps({
        "idle": {"lock": {"timeout": 1, "enabled": False}, "other": 99},
        "list": ["old"], "untouched": "keep",
    }))
    target.chmod(0o640)

    def run(ok=True):
        result = subprocess.run([sys.argv[1]], cwd=root, capture_output=True, text=True)
        assert (result.returncode == 0) == ok, result.stderr
        assert sorted(p.name for p in config.iterdir()) == ["system.json"]

    run()
    assert json.loads(target.read_text()) == {
        "idle": {"lock": {"timeout": 42, "enabled": False}, "other": 99},
        "list": ["replacement"], "untouched": "keep",
    }
    assert target.stat().st_mode & 0o777 == 0o640
    assert json.loads((root / "data/pinnedapps.json").read_text()) == {"apps": ["kitty"]}
    before = target.stat()
    run()
    assert target.stat().st_ino == before.st_ino
    assert target.stat().st_mtime_ns == before.st_mtime_ns

    for invalid in ['{broken', '[]', 'null', '{} {}']:
        target.write_text(invalid)
        run(ok=False)
        assert target.read_text() == invalid

    target.unlink()
    run()
    assert json.loads(target.read_text())["idle"]["lock"]["timeout"] == 42
    assert target.stat().st_mode & 0o777 == 0o600
