root="${1:-$PWD}"
root=$(realpath -- "$root")
if [ ! -f "$root/shell/shell.qml" ]; then
  echo "pangu-dev: run from the Pangu checkout or pass its directory" >&2
  exit 1
fi
if systemctl --user is-active --quiet pangu.service; then
  echo "pangu-dev: stop pangu.service before starting a development instance" >&2
  exit 1
fi
bash "$root/scripts/rebake-shaders.sh"
export PANGU_SHELL_DIR="$root/shell"
exec pangu
