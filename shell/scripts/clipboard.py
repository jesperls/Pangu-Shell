#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time


def connect(path):
    Path(path).parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    db = sqlite3.connect(path, timeout=5)
    db.row_factory = sqlite3.Row
    return db


def initialize(db, schema):
    version = db.execute('PRAGMA user_version').fetchone()[0]
    if version > 1:
        raise ValueError('Clipboard database was created by a newer version')
    if version == 0:
        db.executescript('BEGIN IMMEDIATE;\n' + Path(schema).read_text() + '''
            INSERT INTO clipboard_fts(clipboard_fts) VALUES('rebuild');
            PRAGMA user_version = 1;
            COMMIT;
        ''')


def insert(db, payload, mime, data_dir):
    is_image = mime.startswith('image/')
    if not payload:
        return
    digest = hashlib.md5(payload).hexdigest()
    content = '' if is_image else payload.decode('utf-8', errors='replace')
    preview = '[Image]' if is_image else content if len(content) <= 100 else content[:97] + '...'
    binary_path = ''
    created = None
    try:
        with db:
            db.execute('BEGIN IMMEDIATE')
            existing = db.execute('SELECT binary_path FROM clipboard_items WHERE content_hash = ?', (digest,)).fetchone()
            if is_image:
                if existing and existing['binary_path'] and Path(existing['binary_path']).is_file():
                    binary_path = existing['binary_path']
                else:
                    Path(data_dir).mkdir(parents=True, exist_ok=True, mode=0o700)
                    suffix = {'image/png': '.png', 'image/jpeg': '.jpg', 'image/gif': '.gif',
                              'image/webp': '.webp', 'image/bmp': '.bmp', 'image/svg+xml': '.svg'}.get(mime, '.img')
                    with tempfile.NamedTemporaryFile(dir=data_dir, prefix='clipboard_', suffix=suffix, delete=False) as file:
                        created = Path(file.name)
                        file.write(payload)
                    binary_path = str(created)
            timestamp = time.time_ns() // 1_000_000
            db.execute('''
                INSERT INTO clipboard_items
                    (content_hash, mime_type, preview, full_content, is_image, binary_path,
                     size, pinned, display_index, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?)
                ON CONFLICT(content_hash) DO UPDATE SET
                    updated_at = excluded.updated_at,
                    mime_type = excluded.mime_type,
                    preview = excluded.preview,
                    full_content = excluded.full_content,
                    is_image = excluded.is_image,
                    size = excluded.size,
                    binary_path = excluded.binary_path,
                    display_index = CASE WHEN clipboard_items.pinned = 1
                        THEN clipboard_items.display_index ELSE 0 END
            ''', (digest, mime, preview, content, int(is_image), binary_path, len(payload), timestamp, timestamp))
            db.execute('''
                WITH ranked AS (
                    SELECT id, ROW_NUMBER() OVER (ORDER BY updated_at DESC, id DESC) - 1 AS idx
                    FROM clipboard_items WHERE pinned = 0
                )
                UPDATE clipboard_items SET display_index = (SELECT idx FROM ranked WHERE ranked.id = clipboard_items.id)
                WHERE pinned = 0
            ''')
    except BaseException:
        if created:
            created.unlink(missing_ok=True)
        raise


def capture():
    types = subprocess.run(['wl-paste', '--list-types'], capture_output=True, check=False)
    if types.returncode:
        return None
    offered = types.stdout.decode().splitlines()
    candidates = ['text/uri-list'] + [mime for mime in offered if mime.startswith('image/')]
    candidates += ['text/plain;charset=utf-8', 'text/plain']
    for mime in candidates:
        if mime not in offered:
            continue
        result = subprocess.run(['wl-paste', '--no-newline', '--type', mime], capture_output=True, check=False)
        if result.returncode == 0:
            return result.stdout, mime
    return None


def copy(db, item_id):
    row = db.execute('SELECT mime_type, is_image, binary_path, full_content FROM clipboard_items WHERE id = ?', (item_id,)).fetchone()
    if row is None:
        raise ValueError('Clipboard item no longer exists')
    if row['is_image']:
        path = row['binary_path']
        if not path or not Path(path).is_file():
            raise ValueError('Clipboard image data no longer exists')
        payload = Path(path).read_bytes()
    else:
        payload = (row['full_content'] or '').encode()
    subprocess.run(['wl-copy', '--type', row['mime_type']], input=payload, check=True)


def cleanup(db, data_dir):
    with db:
        db.execute('BEGIN IMMEDIATE')  # Serialize file cleanup with image insertion.
        referenced = {row[0] for row in db.execute('SELECT binary_path FROM clipboard_items WHERE is_image = 1')}
        for path in Path(data_dir).glob('clipboard_*'):
            if str(path) not in referenced and path.is_file():
                path.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('database')
    parser.add_argument('operation', choices=['init', 'capture', 'content', 'delete', 'cleanup', 'list', 'clear', 'pin', 'alias', 'swap', 'copy'])
    parser.add_argument('arguments', nargs='*')
    args = parser.parse_args()
    os.umask(0o077)
    with connect(args.database) as db:
        if args.operation == 'init':
            initialize(db, args.arguments[0])
        elif args.operation == 'capture':
            captured = capture()
            if captured:
                insert(db, *captured, args.arguments[0])
        elif args.operation == 'list':
            rows = db.execute("""
                SELECT id, mime_type, preview, is_image, binary_path, content_hash,
                       size, created_at, pinned, alias, display_index,
                       CASE WHEN mime_type = 'text/uri-list' THEN full_content END AS full_content
                FROM clipboard_items
                ORDER BY pinned DESC, display_index ASC, updated_at DESC, id DESC LIMIT 100
            """)
            print(json.dumps([dict(row) for row in rows]))
        elif args.operation == 'clear':
            db.execute('DELETE FROM clipboard_items WHERE pinned = 0')
            db.commit()
            subprocess.run(['wl-copy', '--clear'], check=False)
            cleanup(db, args.arguments[0])
        elif args.operation == 'alias':
            db.execute('UPDATE clipboard_items SET alias = ? WHERE id = ?',
                       (args.arguments[1] or None, int(args.arguments[0])))
        elif args.operation == 'pin':
            with db:
                db.execute('BEGIN IMMEDIATE')
                item_id = int(args.arguments[0])
                db.execute('UPDATE clipboard_items SET pinned = 1 - pinned, display_index = -1 WHERE id = ?', (item_id,))
                db.execute("""
                    WITH ranked AS (
                        SELECT id, ROW_NUMBER() OVER (
                            PARTITION BY pinned ORDER BY display_index, updated_at DESC, id DESC
                        ) - 1 AS idx FROM clipboard_items
                    )
                    UPDATE clipboard_items SET display_index = (SELECT idx FROM ranked WHERE ranked.id = clipboard_items.id)
                """)
        elif args.operation == 'swap':
            with db:
                db.execute('BEGIN IMMEDIATE')
                first, second = map(int, args.arguments)
                rows = db.execute('SELECT id, pinned, display_index FROM clipboard_items WHERE id IN (?, ?)', (first, second)).fetchall()
                if len(rows) == 2 and rows[0]['pinned'] == rows[1]['pinned']:
                    db.executemany('UPDATE clipboard_items SET display_index = ? WHERE id = ?',
                                   [(rows[1]['display_index'], rows[0]['id']), (rows[0]['display_index'], rows[1]['id'])])
        elif args.operation == 'copy':
            copy(db, int(args.arguments[0]))
        elif args.operation == 'content':
            row = db.execute('SELECT full_content FROM clipboard_items WHERE id = ?', (int(args.arguments[0]),)).fetchone()
            sys.stdout.write(row[0] or '' if row else '')
        elif args.operation == 'delete':
            with db:
                db.execute('BEGIN IMMEDIATE')
                row = db.execute('DELETE FROM clipboard_items WHERE id = ? RETURNING content_hash', (int(args.arguments[0]),)).fetchone()
            if row:
                captured = capture()
                if captured and hashlib.md5(captured[0]).hexdigest() == row[0]:
                    subprocess.run(['wl-copy', '--clear'], check=False)
            cleanup(db, args.arguments[1])
        elif args.operation == 'cleanup':
            cleanup(db, args.arguments[0])


if __name__ == '__main__':
    main()
