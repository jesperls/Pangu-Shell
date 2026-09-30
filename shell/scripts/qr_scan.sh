#!/usr/bin/env bash

for dep in grim slurp zbarimg wl-copy notify-send; do
    if ! command -v "$dep" &> /dev/null; then
        notify-send "QR Scan Error" "Missing dependency: $dep" -u critical
        exit 1
    fi
done

if ! REGION=$(slurp) || [ -z "$REGION" ]; then
    exit 0  # User cancelled
fi

TMP_IMG=$(mktemp) || exit 1
trap 'rm -f "$TMP_IMG"' EXIT
if ! grim -g "$REGION" "$TMP_IMG" 2>/dev/null; then
    notify-send "QR Scan Error" "Screenshot capture failed" -u critical
    exit 1
fi

RESULT=$(zbarimg -q --raw "$TMP_IMG" 2>/dev/null)
status=$? # zbarimg returns 4 when the image contains no barcode.
if [ "$status" -ne 0 ] && [ "$status" -ne 4 ]; then
    notify-send "QR Scan Error" "Barcode recognition failed" -u critical
    exit 1
fi

if [ -n "$RESULT" ]; then
    if ! printf '%s' "$RESULT" | wl-copy; then
        notify-send "QR Scan Error" "Could not copy content to clipboard" -u critical
        exit 1
    fi
    notify-send "QR/Barcode Result" "Content copied to clipboard" -i qr-code
else
    notify-send "QR/Barcode Result" "No code detected" -u low -i dialogue-error
fi
