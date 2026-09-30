import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import subprocess
import sys
import json
from unittest.mock import patch
import unittest

SHELL = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('clipboard', SHELL / 'scripts/clipboard.py')
clipboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clipboard)


class ClipboardTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name) / "image's data"
        self.db = clipboard.connect(str(Path(self.temp.name) / "clipboard's.db"))
        self.addCleanup(self.db.close)
        clipboard.initialize(self.db, SHELL / 'modules/services/clipboard_init.sql')

    def insert(self, value, mime='text/plain'):
        clipboard.insert(self.db, value, mime, self.data)

    def matches(self, word):
        return self.db.execute('SELECT rowid FROM clipboard_fts WHERE clipboard_fts MATCH ?', (word,)).fetchall()

    def test_text_is_preserved(self):
        value = "quote's \\ newline\r\n\n漢字\n".encode()
        self.insert(value)
        row = self.db.execute('SELECT * FROM clipboard_items').fetchone()
        self.assertEqual(row['full_content'].encode(), value)
        self.assertEqual(row['size'], len(value))

    def test_copy_preserves_text_and_image_bytes(self):
        payload = b"quote's\r\n\n"
        self.insert(payload)
        with patch('clipboard.subprocess.run') as run:
            clipboard.copy(self.db, 1)
            self.assertEqual(run.call_args.kwargs['input'], payload)
            self.assertEqual(run.call_args.args[0], ['wl-copy', '--type', 'text/plain'])
        self.insert(b'\x89PNG\x00\xff', 'image/png')
        item_id = self.db.execute('SELECT id FROM clipboard_items WHERE is_image = 1').fetchone()[0]
        with patch('clipboard.subprocess.run') as run:
            clipboard.copy(self.db, item_id)
            self.assertEqual(run.call_args.kwargs['input'], b'\x89PNG\x00\xff')

    def test_index_update_delete_and_metadata(self):
        self.insert(b'alpha')
        self.db.execute("UPDATE clipboard_items SET full_content = 'beta', preview = 'beta'")
        self.assertFalse(self.matches('alpha'))
        self.assertTrue(self.matches('beta'))
        self.db.execute('UPDATE clipboard_items SET pinned = 1')
        self.assertTrue(self.matches('beta'))
        self.db.execute('DELETE FROM clipboard_items')
        self.assertFalse(self.matches('beta'))
        self.db.execute("INSERT INTO clipboard_fts(clipboard_fts, rank) VALUES('integrity-check', 1)")

    def test_duplicate_images_and_missing_file_recovery(self):
        self.insert(b'image bytes', 'image/png')
        self.insert(b'image bytes', 'image/png')
        self.assertEqual(len(list(self.data.iterdir())), 1)
        path = Path(self.db.execute('SELECT binary_path FROM clipboard_items').fetchone()[0])
        path.unlink()
        self.insert(b'image bytes', 'image/png')
        recovered = Path(self.db.execute('SELECT binary_path FROM clipboard_items').fetchone()[0])
        self.assertEqual(recovered.read_bytes(), b'image bytes')
        self.db.execute('DELETE FROM clipboard_items')
        self.db.commit()
        clipboard.cleanup(self.db, self.data)
        self.assertFalse(list(self.data.iterdir()))

    def test_recopied_pin_keeps_position(self):
        self.insert(b'first')
        self.db.execute('UPDATE clipboard_items SET pinned = 1, display_index = 7')
        self.db.commit()
        self.insert(b'first')
        row = self.db.execute('SELECT pinned, display_index FROM clipboard_items').fetchone()
        self.assertEqual(tuple(row), (1, 7))

    def test_legacy_blob_content_and_cli_arguments(self):
        self.insert(b'legacy')
        self.db.execute('UPDATE clipboard_items SET preview = ?, full_content = ?',
                        (sqlite3.Binary(b'legacy'), sqlite3.Binary(b"quote's\r\n\n")))
        self.db.execute('PRAGMA user_version = 0')
        self.db.commit()
        clipboard.initialize(self.db, SHELL / 'modules/services/clipboard_init.sql')
        database = self.db.execute('PRAGMA database_list').fetchone()[2]
        command = [sys.executable, str(SHELL / 'scripts/clipboard.py'), database]
        subprocess.run(command + ['alias', '--', '1', "--quote's"], check=True)
        listed = json.loads(subprocess.check_output(command + ['list']))
        self.assertEqual(listed[0]['alias'], "--quote's")
        self.assertEqual(listed[0]['preview'], 'legacy')
        self.assertEqual(subprocess.check_output(command + ['content', '1']), b"quote's\r\n\n")

    def test_existing_database_is_repaired_once(self):
        self.insert(b'legacy')
        self.db.executescript('''
            DROP TRIGGER clipboard_items_ad;
            CREATE TRIGGER clipboard_items_ad AFTER DELETE ON clipboard_items BEGIN
                DELETE FROM clipboard_fts WHERE rowid = old.id;
            END;
            PRAGMA user_version = 0;
        ''')
        clipboard.initialize(self.db, SHELL / 'modules/services/clipboard_init.sql')
        self.assertTrue(self.matches('legacy'))
        self.db.execute('DELETE FROM clipboard_items')
        self.db.commit()
        self.assertFalse(self.matches('legacy'))
        clipboard.initialize(self.db, SHELL / 'modules/services/clipboard_init.sql')
        self.assertEqual(self.db.execute('PRAGMA user_version').fetchone()[0], 1)


if __name__ == '__main__':
    unittest.main()
