import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from concurrent.futures import ThreadPoolExecutor

SHELL = Path(__file__).resolve().parents[1]
BACKEND = SHELL / 'scripts/notes.py'
spec = importlib.util.spec_from_file_location('notes_backend', BACKEND)
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)


class NotesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="pangu-notes-' ")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def call(self, action, **request):
        return notes.operate(self.root, dict(request, action=action))

    def create(self, title='Test', markdown=False):
        return self.call('create', title=title, isMarkdown=markdown)['id']

    def test_legacy_files_and_literal_content(self):
        (self.root / 'notes').mkdir()
        original = {'order': ['old'], 'notes': {'old': {'title': 'Legacy', 'isMarkdown': True}}}
        (self.root / 'index.json').write_text(json.dumps(original))
        (self.root / 'notes/old.md').write_text('existing\n\n')
        loaded = self.call('read', id='old')
        self.assertEqual(loaded['content'], 'existing\n\n')
        content = "quotes '\" $HOME `command`\n" * 20000
        saved = self.call('save', id='old', content=content, revision=loaded['revision'])
        self.assertEqual(self.call('read', id='old')['content'], content)
        self.assertEqual(saved['revision'], notes.revision(content))
        self.assertEqual(json.loads((self.root / 'index.json').read_text()), original)

    def test_external_change_is_not_overwritten(self):
        key = self.create()
        loaded = self.call('read', id=key)
        path = self.root / 'notes' / (key + '.html')
        path.write_text('external edit')
        with self.assertRaisesRegex(ValueError, 'changed on disk'):
            self.call('save', id=key, content='stale editor', revision=loaded['revision'])
        self.assertEqual(path.read_text(), 'external edit')

    def test_failed_atomic_replace_preserves_file(self):
        key = self.create()
        loaded = self.call('read', id=key)
        with patch.object(notes.os, 'replace', side_effect=OSError('disk failure')):
            with self.assertRaises(OSError):
                self.call('save', id=key, content='new', revision=loaded['revision'])
        self.assertEqual(self.call('read', id=key)['content'], loaded['content'])
        self.assertEqual(len(list((self.root / 'notes').iterdir())), 1)

    def test_index_failure_rolls_back_delete(self):
        key = self.create()
        with patch.object(notes, 'write_index', side_effect=OSError('disk failure')):
            with self.assertRaises(OSError):
                self.call('delete', id=key)
        self.assertIn(key, [item['id'] for item in self.call('list')['notes']])
        self.assertTrue(self.call('read', id=key)['content'])

    def test_delete_retains_recoverable_file(self):
        key = self.create('<tag>')
        content = self.call('read', id=key)['content']
        self.assertIn('&lt;tag&gt;', content)
        self.call('delete', id=key)
        self.assertEqual(self.call('list')['notes'], [])
        self.assertEqual(next((self.root / 'trash').iterdir()).read_text(), content)

    def test_corrupt_index_is_never_replaced(self):
        for content in ('broken', '{"order": [], "notes": {"../escape": {}}}'):
            (self.root / 'index.json').write_text(content)
            with self.assertRaises(ValueError):
                self.create()
            self.assertEqual((self.root / 'index.json').read_text(), content)

    def test_concurrent_creates_and_metadata_changes(self):
        def create(number):
            result = subprocess.run([sys.executable, str(BACKEND), str(self.root)],
                                    input=json.dumps({'action': 'create', 'title': str(number)}),
                                    capture_output=True, text=True, check=True)
            return json.loads(result.stdout)['id']
        with ThreadPoolExecutor(max_workers=4) as executor:
            ids = list(executor.map(create, range(8)))
        self.assertEqual(len(self.call('list')['notes']), 8)
        self.call('rename', id=ids[0], title='Renamed')
        self.call('move', id=ids[1], direction=-1)
        result = self.call('list')['notes']
        self.assertEqual(set(ids), {note['id'] for note in result})
        self.assertEqual(next(note['title'] for note in result if note['id'] == ids[0]), 'Renamed')


@unittest.skipUnless(shutil.which('qs'), 'Quickshell is required')
class NotesServiceTest(unittest.TestCase):
    def test_shared_drafts_and_ordered_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'config').mkdir()
            (root / 'runtime').mkdir(mode=0o700)
            (root / 'config/qmldir').write_text('singleton Paths 1.0 Paths.qml\n')
            (root / 'config/Paths.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {\n'
                + 'readonly property string notesDir: ' + json.dumps(str(root / 'data')) + '\n'
                + 'function script(name) { return ' + json.dumps(str(SHELL / 'scripts') + '/') + ' + name; }\n}\n')
            shutil.copy(SHELL / 'modules/services/NotesService.qml', root / 'NotesService.qml')
            (root / 'qmldir').write_text('singleton NotesService 1.0 NotesService.qml\n')
            (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "config"
import "."
ShellRoot {
    property int step: 0
    property string noteId: ""
    FileView {
        id: externalEditor
        preload: false
        atomicWrites: true
        onSaved: {
            NotesService.edit(noteId, "unsaved local edit", "first-screen");
            NotesService.flush();
            step = 5;
        }
    }
    Timer {
        interval: 30; running: true; repeat: true
        onTriggered: {
            if (!NotesService.ready || NotesService.currentJob || NotesService.pending.length) return;
            if (step === 0) {
                NotesService.create("Native test", true, "first-screen"); step++;
            } else if (step === 1) {
                noteId = NotesService.notes[0].id;
                NotesService.load(noteId); step++;
            } else if (step === 2 && NotesService.document(noteId).loaded) {
                NotesService.edit(noteId, "first screen", "first-screen");
                NotesService.flush();
                NotesService.edit(noteId, "second screen", "second-screen");
                NotesService.flush();
                step++;
            } else if (step === 3 && !NotesService.document(noteId).dirty) {
                NotesService.reload(noteId); step++;
            } else if (step === 4 && NotesService.document(noteId).loaded) {
                console.log(NotesService.document(noteId).content === "second screen" && !NotesService.error
                    ? "CHECK_PASSED" : "CHECK_FAILED");
                externalEditor.path = Paths.notesDir + "/notes/" + noteId + ".md";
                step = 6;
                externalEditor.setText("external edit");
            } else if (step === 5 && NotesService.error) {
                console.log(NotesService.document(noteId).dirty && NotesService.document(noteId).content === "unsaved local edit"
                    ? "CONFLICT_PASSED" : "CHECK_FAILED");
                Qt.quit();
            }
        }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', XDG_RUNTIME_DIR=str(root / 'runtime'),
                       XDG_CACHE_HOME=str(root / 'cache'), QML_DISABLE_DISK_CACHE='1')
            env.pop('WAYLAND_DISPLAY', None)
            result = subprocess.run(['qs', '-p', str(root / 'shell.qml')], env=env,
                                    capture_output=True, text=True, timeout=15)
            log = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, log)
            self.assertIn('CHECK_PASSED', log)
            self.assertIn('CONFLICT_PASSED', log)
            for error in ('TypeError', 'ReferenceError', 'Binding loop', 'CHECK_FAILED'):
                self.assertNotIn(error, log)
            self.assertEqual(next((root / 'data/notes').iterdir()).read_text(), 'external edit')
