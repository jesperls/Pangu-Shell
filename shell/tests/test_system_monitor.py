import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


def load_system_monitor():
    spec = importlib.util.spec_from_file_location("system_monitor", SCRIPTS / "system_monitor.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SystemMonitorDiskTypeTest(unittest.TestCase):
    def test_mount_source_from_mountinfo_handles_btrfs_luks_and_spaces(self):
        sm = load_system_monitor()
        lines = [
            "26 1 0:26 /@ / rw,relatime shared:1 - btrfs /dev/mapper/cryptroot rw,compress=zstd:3,subvol=/@",
            "99 26 259:2 / /mnt/my\\040games rw,relatime - ext4 /dev/nvme0n1p2 rw",
        ]
        with mock.patch.object(sm.os.path, "realpath", side_effect=lambda p: p):
            self.assertEqual(
                sm.SystemMonitor._mount_source_from_mountinfo("/", lines),
                "/dev/mapper/cryptroot",
            )
            self.assertEqual(
                sm.SystemMonitor._mount_source_from_mountinfo("/mnt/my games", lines),
                "/dev/nvme0n1p2",
            )
            self.assertEqual(
                sm.SystemMonitor._mount_source_from_mountinfo("/mnt/my games/Steam", lines),
                "/dev/nvme0n1p2",
            )

    def test_detect_disk_types_uses_mountinfo_dm_slave(self):
        sm = load_system_monitor()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            nvme_block = root / "sys/devices/nvme0n1"
            nvme_part = nvme_block / "nvme0n1p2"
            (nvme_block / "queue").mkdir(parents=True)
            (nvme_block / "queue/rotational").write_text("0\n")
            nvme_part.mkdir(parents=True)
            (nvme_part / "partition").write_text("2\n")

            dm_block = root / "sys/devices/dm-0"
            (dm_block / "slaves").mkdir(parents=True)
            (dm_block / "slaves/nvme0n1p2").symlink_to(nvme_part)

            dev_block = root / "sys/dev/block"
            dev_block.mkdir(parents=True)
            (dev_block / "253:0").symlink_to(dm_block)

            fake_stat = mock.MagicMock()
            fake_stat.st_rdev = sm.os.makedev(253, 0)
            orig_stat = sm.os.stat
            orig_realpath = sm.os.path.realpath

            def fake_os_stat(p, *args, **kwargs):
                if p == "/dev/mapper/cryptroot":
                    return fake_stat
                return orig_stat(p, *args, **kwargs)

            def fake_realpath(p):
                if isinstance(p, str) and p.startswith("/sys/"):
                    return orig_realpath(str(root / p.lstrip("/")))
                return orig_realpath(p)

            with mock.patch.object(sm.os, "stat", side_effect=fake_os_stat), \
                 mock.patch.object(sm.os.path, "realpath", side_effect=fake_realpath):
                block = sm.SystemMonitor._sysfs_block_for_source("/dev/mapper/cryptroot")
                self.assertEqual(block, orig_realpath(str(nvme_block)))

            monitor = sm.SystemMonitor.__new__(sm.SystemMonitor)
            with mock.patch.object(sm.SystemMonitor, "_mount_source_from_mountinfo", return_value="/dev/mapper/cryptroot"), \
                 mock.patch.object(sm.SystemMonitor, "_sysfs_block_for_source", return_value=str(nvme_block)):
                types = monitor._detect_disk_types(["/"])
                self.assertEqual(types["/"], "ssd")


if __name__ == "__main__":
    unittest.main()
