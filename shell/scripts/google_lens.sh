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
uploadResponse=$(curl -sS -f -F "files[]=@$IMAGE_PATH" 'https://uguu.se/upload' 2>&1)
curlExit=$?
set -e

if [[ $curlExit -ne 0 ]]; then
	notify-send -u critical "Google Lens" "Upload failed (curl error $curlExit)" >&2
	echo "ERROR: Upload failed with curl exit code $curlExit" >&2
	echo "Response: $uploadResponse" >&2
	exit 1
fi

imageLink=$(echo "$uploadResponse" | jq -r '.files[0].url' 2>&1)
jqExit=$?

if [[ $jqExit -ne 0 ]] || [[ -z "$imageLink" ]] || [[ "$imageLink" == "null" ]]; then
	notify-send -u critical "Google Lens" "Failed to parse upload response" >&2
	echo "ERROR: Failed to parse upload response" >&2
	echo "Response: $uploadResponse" >&2
	exit 1
fi

echo "Image uploaded successfully: $imageLink" >&2

lensUrl="https://lens.google.com/uploadbyurl?url=${imageLink}"
echo "Opening in Google Lens: $lensUrl" >&2

xdg-open "$lensUrl" 2>&1 || true

rm -f "$IMAGE_PATH"
notify-send "Google Lens" "Image opened in browser successfully"
echo "Success: Google Lens opened" >&2
