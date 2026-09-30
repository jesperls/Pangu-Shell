#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
	echo "Use: $0 <backend> <database> <data-dir>" >&2
	exit 1
fi

export PANGU_CLIPBOARD_BACKEND="$1" PANGU_CLIPBOARD_DB="$2" PANGU_CLIPBOARD_DATA="$3"
exec wl-paste --watch bash -c '
    cat >/dev/null
    if [ "${CLIPBOARD_STATE:-data}" = data ] && python3 "$PANGU_CLIPBOARD_BACKEND" "$PANGU_CLIPBOARD_DB" capture "$PANGU_CLIPBOARD_DATA"; then
        echo REFRESH_LIST
    fi
'
