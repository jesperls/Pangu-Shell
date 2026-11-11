#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
in_file="${2:-}"

if [ -z "$mode" ] || [ -z "$in_file" ] || [ ! -f "$in_file" ]; then
    echo "Usage: process_clip.sh <probe|trim|compress> <file> [start_sec] [end_sec]" >&2
    exit 1
fi

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/pangu/replay-thumbs"
mkdir -p "$runtime_dir"

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
        out_file="${base}_trim_$(date +%H%M%S).mp4"
        ffmpeg -y -v error -ss "$start_sec" -to "$end_sec" -i "$in_file" -c copy -movflags +faststart -- "$out_file"
        printf 'file://%s\r\n' "$out_file" | wl-copy --type text/uri-list 2>/dev/null || true
        printf '%s\n' "$out_file"
        ;;

    compress)
        start_sec="${3:-}"
        end_sec="${4:-}"
        total_dur="$(probe_duration)"
        clip_dur="$total_dur"
        trim_args=()
        if [ -n "$start_sec" ] && [ -n "$end_sec" ]; then
            clip_dur="$(awk -v s="$start_sec" -v e="$end_sec" -v t="$total_dur" 'BEGIN {
                d = (e + 0) - (s + 0);
                if (d <= 0.2) d = t + 0;
                printf "%.3f", d
            }')"
            trim_args=(-ss "$start_sec" -to "$end_sec")
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
        out_file="${base}_discord_$(date +%H%M%S).mp4"

        if ! ffmpeg -y -v error "${trim_args[@]}" -i "$in_file" \
            -vf "scale='min(1920,iw)':-2" \
            -c:v h264_nvenc -preset p4 -b:v "${vbit}k" -maxrate "${maxbit}k" -bufsize "${bufbit}k" \
            -c:a aac -b:a 128k -movflags +faststart -- "$out_file" 2>/dev/null; then
            ffmpeg -y -v error "${trim_args[@]}" -i "$in_file" \
                -vf "scale='min(1920,iw)':-2" \
                -c:v libx264 -preset veryfast -b:v "${vbit}k" -maxrate "${maxbit}k" -bufsize "${bufbit}k" \
                -c:a aac -b:a 128k -movflags +faststart -- "$out_file"
        fi
        printf 'file://%s\r\n' "$out_file" | wl-copy --type text/uri-list 2>/dev/null || true
        printf '%s\n' "$out_file"
        ;;

    *)
        echo "Unknown mode: $mode" >&2
        exit 1
        ;;
esac
