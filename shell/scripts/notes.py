#!/usr/bin/env python3

import fcntl
import hashlib
import html
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from datetime import datetime, timezone
from uuid import uuid4


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def revision(content):
    return hashlib.sha256(content.encode()).hexdigest()


def atomic_write(path, content):
    descriptor, temporary = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        Path(temporary).unlink(missing_ok=True)


def read_index(root):
    path = root / 'index.json'
    text = path.read_text() if path.exists() else ''
    data = json.loads(text) if text.strip() else {'order': [], 'notes': {}}
    if not isinstance(data, dict) or not isinstance(data.get('order'), list) or not isinstance(data.get('notes'), dict):
        raise ValueError('Invalid notes index; restore index.json before editing notes')
    for key, value in data['notes'].items():
        if not re.fullmatch(r'[A-Za-z0-9_-]+', key) or not isinstance(value, dict):
            raise ValueError('Invalid note metadata')
        if not isinstance(value.get('title', ''), str) or not isinstance(value.get('isMarkdown', False), bool):
            raise ValueError('Invalid note title or format')
    if any(not isinstance(key, str) or key not in data['notes'] for key in data['order']):
        raise ValueError('Invalid notes order')
    data['order'] = list(dict.fromkeys(data['order'] + list(data['notes'])))
    return data


def note_path(root, index, key):
    if key not in index['notes']:
        raise ValueError('This note no longer exists')
    return root / 'notes' / (key + ('.md' if index['notes'][key].get('isMarkdown') else '.html'))


def listing(root, index):
    result = [dict(index['notes'][key], id=key, title=index['notes'][key].get('title') or 'Untitled',
                 isCreateButton=False) for key in index['order']]
    for note in result:
        path = note_path(root, index, note['id'])
        if path.exists():
            modified = datetime.fromtimestamp(path.stat().st_mtime, timezone.utc)
            try:
                previous = datetime.fromisoformat(note.get('modified', '').replace('Z', '+00:00'))
                if previous.tzinfo is None:
                    previous = previous.replace(tzinfo=timezone.utc)
                modified = max(modified, previous)
            except (ValueError, TypeError):
                pass
            note['modified'] = modified.isoformat()
    return result


def write_index(root, index):
    atomic_write(root / 'index.json', json.dumps(index, ensure_ascii=False, indent=2))


def operate(root, request):
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    (root / 'notes').mkdir(exist_ok=True)
    with (root / '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        index = read_index(root)
        action = request['action']
        key = request.get('id', '')
        if action == 'list':
            return {'notes': listing(root, index)}
        if action == 'read':
            content = note_path(root, index, key).read_text()
            return {'id': key, 'content': content, 'revision': revision(content)}
        if action == 'save':
            path = note_path(root, index, key)
            previous = path.read_text()
            if revision(previous) != request['revision']:
                raise ValueError('Note changed on disk. Copy your unsaved text before reloading it')
            content = request['content']
            atomic_write(path, content)
            return {'id': key, 'revision': revision(content)}
        if action == 'create':
            key = str(uuid4())
            title = request.get('title', '').strip() or 'Untitled Note'
            markdown = bool(request.get('isMarkdown'))
            now = timestamp()
            index['notes'][key] = dict(title=title, created=now, modified=now, isMarkdown=markdown)
            index['order'].insert(0, key)
            content = '# ' + title + '\n\n' if markdown else '<h1>' + html.escape(title) + '</h1><p></p>'
            path = note_path(root, index, key)
            atomic_write(path, content)
            try:
                write_index(root, index)
            except Exception:
                path.unlink()
                raise
        elif action == 'rename':
            note_path(root, index, key)
            title = request['title'].strip()
            if not title:
                raise ValueError('A note needs a title')
            index['notes'][key]['title'] = title
            index['notes'][key]['modified'] = timestamp()
            write_index(root, index)
        elif action == 'move':
            note_path(root, index, key)
            source = index['order'].index(key)
            target = max(0, min(len(index['order']) - 1, source + int(request['direction'])))
            index['order'].insert(target, index['order'].pop(source))
            write_index(root, index)
        elif action == 'delete':
            path = note_path(root, index, key)
            trash = root / 'trash'
            trash.mkdir(exist_ok=True)
            destination = trash / (str(uuid4()) + '-' + path.name)
            os.replace(path, destination)
            del index['notes'][key]
            index['order'].remove(key)
            try:
                write_index(root, index)
            except Exception:
                os.replace(destination, path)
                raise
        else:
            raise ValueError('Unknown notes operation')
        return {'id': key, 'notes': listing(root, index)}


def main():
    try:
        result = operate(sys.argv[1], json.load(sys.stdin))
        print(json.dumps(dict(result, ok=True), ensure_ascii=False))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
