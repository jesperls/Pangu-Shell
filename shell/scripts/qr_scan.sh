#!/usr/bin/env bash
set -euo pipefail

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send "$@" || true
}

TMP_IMG="${1:-}"
DEPS=(zbarimg wl-copy notify-send)
if [ -z "$TMP_IMG" ]; then
    DEPS+=(grim slurp)
fi

for dep in "${DEPS[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "QR Scan Error: Missing dependency: $dep" >&2
        notify "QR Scan Error" "Missing dependency: $dep" -u critical
        exit 1
    fi
done

if [ -z "$TMP_IMG" ]; then
    if ! REGION=$(slurp) || [ -z "$REGION" ]; then
        exit 0
    fi
    TMP_IMG=$(mktemp) || exit 1
    trap 'rm -f "$TMP_IMG"' EXIT
    if ! grim -g "$REGION" "$TMP_IMG" 2>/dev/null; then
        notify "QR Scan Error" "Screenshot capture failed" -u critical
        exit 1
    fi
elif [ ! -r "$TMP_IMG" ]; then
    notify "QR Scan Error" "Cannot read selected image" -u critical
    exit 1
fi

status=0
RESULT=$(zbarimg -q --raw "$TMP_IMG" 2>/dev/null) || status=$?
# zbarimg returns 4 when the image contains no barcode.
if [ "$status" -ne 0 ] && [ "$status" -ne 4 ]; then
    notify "QR Scan Error" "Barcode recognition failed" -u critical
    exit 1
fi

if [ -n "$RESULT" ]; then
    if ! printf '%s' "$RESULT" | wl-copy; then
        notify "QR Scan Error" "Could not copy content to clipboard" -u critical
        exit 1
    fi
    notify "QR/Barcode Result" "Content copied to clipboard" -i qr-code
else
    notify "QR/Barcode Result" "No code detected" -u low -i dialog-error
fi
