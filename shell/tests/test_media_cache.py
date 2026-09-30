from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import media_cache
import lockwall
import thumbgen


class MediaCacheTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_failed_render_preserves_previous_image(self):
        destination = self.root / 'image.jpg'
        destination.write_bytes(b'previous')
        def render(command, **kwargs):
            Path(command[-1]).write_bytes(b'partial')
            return subprocess.CompletedProcess(command, 1, stderr='failed')
        with patch('media_cache.subprocess.run', side_effect=render):
            with self.assertRaises(RuntimeError):
                media_cache.render_atomic(['renderer'], destination, 1)
        self.assertEqual(destination.read_bytes(), b'previous')
        self.assertEqual(list(self.root.iterdir()), [destination])

    def test_empty_render_is_not_cached(self):
        with patch('media_cache.subprocess.run', return_value=subprocess.CompletedProcess([], 0, stderr='')):
            with self.assertRaises(RuntimeError):
                media_cache.render_atomic(['renderer'], self.root / 'image.jpg', 1)
        self.assertFalse(list(self.root.iterdir()))

    def test_same_named_lock_wallpapers_have_distinct_paths(self):
        paths = []
        with patch('lockwall.render_atomic', side_effect=lambda command, destination, timeout: paths.append(destination)):
            lockwall.generate('/first/video.mp4', self.root)
            lockwall.generate('/second/video.mp4', self.root)
        self.assertNotEqual(paths[0], paths[1])

    def test_short_video_retries_without_seeking(self):
        with patch('thumbgen.render_atomic', side_effect=[RuntimeError('no frame'), None]) as render:
            self.assertTrue(thumbgen.generate(self.root / 'short.mp4', self.root / 'short.jpg'))
        self.assertIn('-ss', render.call_args_list[0].args[0])
        self.assertNotIn('-ss', render.call_args_list[1].args[0])

    def test_hidden_directories_are_excluded(self):
        (self.root / '.hidden').mkdir()
        (self.root / '.hidden' / 'image.png').touch()
        (self.root / 'image.png').touch()
        self.assertEqual(list(thumbgen.media_files(self.root)), [self.root / 'image.png'])


if __name__ == '__main__':
    unittest.main()
