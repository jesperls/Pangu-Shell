#!/usr/bin/env bash
set -euo pipefail

clip_path="${1:-}"
[ -n "$clip_path" ] || exit 0

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/pangu"
mkdir -p "$runtime_dir"
tmp_file="$runtime_dir/.last-replay.$$"
printf '%s\n' "$clip_path" > "$tmp_file"
mv -f "$tmp_file" "$runtime_dir/last-replay"
