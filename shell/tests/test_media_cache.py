from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import media_cache
import lockwall
import matugen_palette
import thumbgen
import wallpaper_files


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

    def test_wallpaper_scanner_follows_aliases_without_recursing_cycles(self):
        actual = self.root / 'actual'
        actual.mkdir()
        (actual / 'WALL.BMP').touch()
        (actual / 'video.MP4').touch()
        (actual / '.hidden.png').touch()
        (actual / 'back').symlink_to(self.root, target_is_directory=True)
        (self.root / 'linked').symlink_to(actual, target_is_directory=True)
        (self.root / 'file.PNG').symlink_to(actual / 'WALL.BMP')
        (self.root / 'missing.png').symlink_to(self.root / 'missing')
        discovered = wallpaper_files.discover(self.root)
        self.assertEqual(set(discovered['files']), {str(actual / 'WALL.BMP'), str(actual / 'video.MP4'),
            str(self.root / 'linked/WALL.BMP'), str(self.root / 'linked/video.MP4'), str(self.root / 'file.PNG')})
        self.assertEqual(set(discovered['directories']), {str(actual), str(self.root / 'linked')})
        self.assertEqual(set(map(str, thumbgen.media_files(self.root))), set(discovered['files']))

    def test_scanner_and_thumbnails_share_expanded_fallback_paths(self):
        (self.root / 'empty').mkdir()
        (self.root / 'fallback').mkdir()
        image = self.root / 'fallback/line\nwith quotes \' and Ö.PNG'
        image.touch()
        result = wallpaper_files.scan(str(self.root / 'empty'), str(self.root / 'fallback'))
        self.assertTrue(result['fallback'])
        self.assertEqual(result['files'], [str(image)])
        with patch.dict('os.environ', {'HOME': str(self.root)}):
            self.assertEqual(wallpaper_files.discover('~/fallback')['files'], [str(image)])

    def test_thumbnail_card_keeps_landscape_dimensions(self):
        with patch('thumbgen.render_atomic') as render:
            self.assertTrue(thumbgen.generate(self.root / 'image.PNG', self.root / 'output.jpg'))
        self.assertIn('320x200', render.call_args.args[0])
        self.assertIn('crop=320:200', ' '.join(media_cache.frame_command('video.mp4', thumbnail=True)))

    def test_missing_user_wallpaper_dir_uses_packaged_fallbacks(self):
        packaged = Path(__file__).resolve().parents[1] / 'assets/wallpapers'
        result = wallpaper_files.scan(str(self.root / 'missing-wallpapers'), str(packaged))
        self.assertTrue(result['fallback'])
        self.assertGreaterEqual(len(result['files']), 2)
        for item in result['files']:
            self.assertTrue(Path(item).is_file())

    def test_matugen_palette_writes_atomically_into_custom_cache_dir(self):
        assets = Path(__file__).resolve().parents[1] / 'assets/matugen'
        custom_cache = self.root / 'cache with "quotes" and spaces' / 'pangu' / 'colors.json'

        def fake_matugen(command, check):
            cfg_path = Path(command[command.index('-c') + 1])
            cfg_text = cfg_path.read_text()
            for line in cfg_text.splitlines():
                if line.startswith('output_path ='):
                    out_file = Path(line.split('=', 1)[1].strip().strip('"').replace('\\"', '"'))
                    out_file.write_text('{"background":"#0c0d11"}\n')

        with patch('matugen_palette.subprocess.run', side_effect=fake_matugen) as run_mock:
            matugen_palette.generate(
                '/wall.jpg',
                str(assets / 'colors.json'),
                str(assets / 'config.toml'),
                'scheme-tonal-spot',
                'dark',
                str(custom_cache),
            )
        self.assertEqual(run_mock.call_count, 1)
        self.assertEqual(custom_cache.read_text(), '{"background":"#0c0d11"}\n')
        self.assertEqual(list(custom_cache.parent.iterdir()), [custom_cache])


if __name__ == '__main__':
    unittest.main()
