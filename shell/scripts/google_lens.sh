#!/usr/bin/env bash

set -euo pipefail

IMAGE_PATH="${1:-}"
if [[ -z "$IMAGE_PATH" ]]; then
	echo "ERROR: no image path given" >&2
	exit 1
fi

if [[ ! -f "$IMAGE_PATH" ]]; then
	notify-send -u critical "Google Lens" "No image found at $IMAGE_PATH" >&2
	echo "ERROR: Image file not found at $IMAGE_PATH" >&2
	exit 1
fi

if [[ ! -r "$IMAGE_PATH" ]]; then
	notify-send -u critical "Google Lens" "Cannot read image at $IMAGE_PATH" >&2
	echo "ERROR: Image file not readable at $IMAGE_PATH" >&2
	exit 1
fi

for cmd in curl jq xdg-open notify-send; do
	if ! command -v "$cmd" &>/dev/null; then
		echo "ERROR: Missing required command: $cmd" >&2
		exit 1
	fi
done

notify-send -u normal "Google Lens" "Uploading image for analysis..."

echo "Uploading image to uguu.se..." >&2

set +e
uploadResponse=$(curl -sS -f --max-time 30 -F "files[]=@$IMAGE_PATH" 'https://uguu.se/upload' 2>&1)
curlExit=$?
set -e

if [[ $curlExit -ne 0 ]]; then
	rm -f "$IMAGE_PATH"
	notify-send -u critical "Google Lens" "Upload failed (curl error $curlExit)" >&2
	echo "ERROR: Upload failed with curl exit code $curlExit" >&2
	exit 1
fi

imageLink=$(printf '%s' "$uploadResponse" | jq -r '.files[0].url // empty' 2>/dev/null || true)

if [[ ! "$imageLink" =~ ^https:// ]]; then
	rm -f "$IMAGE_PATH"
	notify-send -u critical "Google Lens" "Failed to parse upload response" >&2
	echo "ERROR: Invalid upload URL in response" >&2
	exit 1
fi

encodedLink=$(printf '%s' "$imageLink" | jq -sRr @uri)
lensUrl="https://lens.google.com/uploadbyurl?url=${encodedLink}"

xdg-open "$lensUrl" >/dev/null 2>&1 || true

rm -f "$IMAGE_PATH"
notify-send "Google Lens" "Image opened in browser successfully"
