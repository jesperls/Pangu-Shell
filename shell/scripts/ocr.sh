#!/usr/bin/env bash

for dep in grim slurp tesseract wl-copy notify-send; do
    if ! command -v "$dep" &> /dev/null; then
        notify-send "OCR Error" "Missing dependency: $dep" -u critical
        exit 1
    fi
done

if ! REGION=$(slurp) || [ -z "$REGION" ]; then
    exit 0  # User cancelled
fi

if [ -n "${1:-}" ]; then
    LANGS="$1"
else
    LANGS="eng+spa"
fi

TMP_IMG=$(mktemp) || exit 1
trap 'rm -f "$TMP_IMG"' EXIT
if ! grim -g "$REGION" "$TMP_IMG" 2>/dev/null; then
    notify-send "OCR Error" "Screenshot capture failed" -u critical
    exit 1
fi

if ! TEXT=$(tesseract "$TMP_IMG" - -l "$LANGS" 2>/dev/null); then
    notify-send "OCR Error" "Text recognition failed" -u critical
    exit 1
fi

TEXT=$(printf '%s' "$TEXT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

if [ -n "$TEXT" ]; then
    if ! printf '%s' "$TEXT" | wl-copy; then
        notify-send "OCR Error" "Could not copy text to clipboard" -u critical
        exit 1
    fi
    notify-send "OCR Result" "Text copied to clipboard" -i edit-paste
else
    notify-send "OCR Result" "No text detected" -u low -i dialogue-error
fi
