#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
in_file="${2:-}"

if [ -z "$mode" ] || [ -z "$in_file" ] || [ ! -f "$in_file" ]; then
    echo "Usage: process_clip.sh <probe|trim|compress> <file> [start_sec] [end_sec]" >&2
    exit 1
fi

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pangu/replay-thumbs"
mkdir -p "$runtime_dir"

copy_file_uri() {
    local abs_path uri
    abs_path="$(readlink -f -- "$1" 2>/dev/null || printf '%s' "$1")"
    uri="$(python3 -c 'import urllib.parse, sys; print("file://" + urllib.parse.quote(sys.argv[1]))' "$abs_path" 2>/dev/null || printf 'file://%s' "$abs_path")"
    printf '%s\r\n' "$uri" | wl-copy --type text/uri-list 2>/dev/null || true
}

probe_duration() {
    local dur
    dur="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -- "$in_file" 2>/dev/null || true)"
    awk -v d="${dur:-0}" 'BEGIN { if (d + 0 <= 0) print "1.0"; else printf "%.3f", d + 0 }'
}

case "$mode" in
    probe)
        dur="$(probe_duration)"
        size_bytes="$(stat -c '%s' -- "$in_file" 2>/dev/null || echo 0)"
        hash="$(printf '%s:%s' "$in_file" "$size_bytes" | sha256sum | cut -c1-16)"
        thumb="$runtime_dir/${hash}.jpg"
        if [ ! -f "$thumb" ]; then
            seek="$(awk -v d="$dur" 'BEGIN { printf "%.2f", (d > 1.0 ? 0.5 : 0.0) }')"
            ffmpeg -y -v error -ss "$seek" -i "$in_file" -frames:v 1 -vf "scale=480:-1" -- "$thumb" 2>/dev/null || thumb=""
        fi
        jq -cn \
            --arg duration "$dur" \
            --arg sizeBytes "$size_bytes" \
            --arg poster "$thumb" \
            '{duration: ($duration | tonumber), sizeBytes: ($sizeBytes | tonumber), poster: $poster}'
        ;;

    trim)
        start_sec="${3:-0}"
        end_sec="${4:-0}"
        base="${in_file%.*}"
        out_file="${base}_trim_$(date +%H%M%S)_$$.mp4"
        ffmpeg -y -v error -ss "$start_sec" -to "$end_sec" -i "$in_file" -c copy -movflags +faststart -- "$out_file"
        copy_file_uri "$out_file"
        printf '%s\n' "$out_file"
        ;;

    compress)
        start_sec="${3:-}"
        end_sec="${4:-}"
        total_dur="$(probe_duration)"
        clip_dur="$total_dur"
        trim_args=()
        if [ -n "$start_sec" ] && [ -n "$end_sec" ]; then
            valid_trim="$(awk -v s="$start_sec" -v e="$end_sec" 'BEGIN { d = (e + 0) - (s + 0); if (d > 0.2) printf "%.3f", d }')"
            if [ -n "$valid_trim" ]; then
                clip_dur="$valid_trim"
                trim_args=(-ss "$start_sec" -to "$end_sec")
            fi
        fi
        vbit="$(awk -v d="$clip_dur" 'BEGIN {
            target_kbits = 9.1 * 1024 * 8;
            kbps = int((target_kbits / (d > 1 ? d : 1)) - 128);
            if (kbps < 350) kbps = 350;
            if (kbps > 18000) kbps = 18000;
            print kbps
        }')"
        maxbit="$(( vbit * 115 / 100 ))"
        bufbit="$(( vbit * 2 ))"
        base="${in_file%.*}"
        out_file="${base}_discord_$(date +%H%M%S)_$$.mp4"

        if ! ffmpeg -y -v error "${trim_args[@]}" -i "$in_file" \
            -vf "scale='min(1920,iw)':-2" \
            -c:v h264_nvenc -preset p4 -b:v "${vbit}k" -maxrate "${maxbit}k" -bufsize "${bufbit}k" \
            -c:a aac -b:a 128k -movflags +faststart -- "$out_file" 2>/dev/null; then
            ffmpeg -y -v error "${trim_args[@]}" -i "$in_file" \
                -vf "scale='min(1920,iw)':-2" \
                -c:v libx264 -preset veryfast -b:v "${vbit}k" -maxrate "${maxbit}k" -bufsize "${bufbit}k" \
                -c:a aac -b:a 128k -movflags +faststart -- "$out_file"
        fi
        copy_file_uri "$out_file"
        printf '%s\n' "$out_file"
        ;;

    *)
        echo "Unknown mode: $mode" >&2
        exit 1
        ;;
esac
