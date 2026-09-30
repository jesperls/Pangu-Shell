#!/usr/bin/env bash

if [ -z "$1" ]; then
	echo "Use: $0 /path/to/wallpaper [shader_path] [monitor_target]"
	exit 1
fi

WALLPAPER="$1"
SHADER="$2"
MONITOR="${3:-ALL}"

SOCKET="${XDG_RUNTIME_DIR:-/tmp}/pangu/mpv-${MONITOR}.sock"
mkdir -p "$(dirname "$SOCKET")"

# Quickshell only reaps the child it spawned, so a renderer orphaned by a shell
# crash or upgrade would keep holding this monitor's IPC socket.
if command -v pkill >/dev/null; then
	pkill -f "input-ipc-server=${SOCKET}" 2>/dev/null || true
	for _ in $(seq 1 20); do
		pgrep -f "input-ipc-server=${SOCKET}" >/dev/null 2>&1 || break
		sleep 0.05
	done
fi

MPV_OPTS="no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 load-scripts=no input-ipc-server=$SOCKET"

if [ -n "$SHADER" ] && [ -f "$SHADER" ]; then
	MPV_OPTS="$MPV_OPTS glsl-shaders=$SHADER"
fi

exec mpvpaper -o "$MPV_OPTS" "$MONITOR" "$WALLPAPER"
