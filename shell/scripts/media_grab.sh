#!/usr/bin/env bash
set -euo pipefail

mode="${1:-video}"
url="${2:-}"

if [ -z "$url" ]; then
    echo "Usage: media_grab.sh <video|audio> <url>" >&2
    exit 1
fi

dl_dir="$(xdg-user-dir DOWNLOAD 2>/dev/null || true)"
if [ -z "$dl_dir" ]; then
    dl_dir="$HOME/Downloads"
fi
mkdir -p "$dl_dir"

dl_args=()
if command -v aria2c >/dev/null 2>&1; then
    dl_args=(--downloader aria2c --downloader-args "aria2c:-x 8 -s 8 -k 1M --summary-interval=0")
fi

common_args=(
    --newline
    --no-playlist
    --no-warnings
    --progress-template "download:PANGU_PROG:%(progress._percent_str)s"
    --print "after_move:PANGU_FILE:%(filepath)s"
    -o "$dl_dir/%(title).100B [%(id)s].%(ext)s"
)

if [ "$mode" = "audio" ]; then
    exec yt-dlp "${common_args[@]}" "${dl_args[@]}" -x --audio-format mp3 --audio-quality 0 -- "$url"
else
    exec yt-dlp "${common_args[@]}" "${dl_args[@]}" -f "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b" --merge-output-format mp4 -- "$url"
fi
