{
  lib,
  pkgs,
  pangu,
}:
pkgs.runCommand "pangu-runtime-check" { nativeBuildInputs = [ pkgs.bash ]; } ''
  export PATH=${lib.makeBinPath pangu.runtimeInputs}
  for cmd in qs bash find python3 jq grep sed awk pkill pgrep hypridle gtk-launch \
    xdg-terminal-exec matugen mpvpaper grim slurp wl-copy ddcutil brightnessctl \
    tesseract zbarimg swappy notify-send wtype mpv ydotool pw-cat \
    nmcli bluetoothctl hyprpicker playerctl gpu-screen-recorder tmux wpctl; do
    command -v "$cmd" >/dev/null || { echo "Pangu runtime is missing: $cmd" >&2; exit 1; }
  done
  python3 -c "import numpy"
  ${lib.getExe pangu} help >/dev/null

  cleanHome="$(mktemp -d)"
  export HOME="$cleanHome"
  export XDG_CONFIG_HOME="$cleanHome/cfg"
  export XDG_DATA_HOME="$cleanHome/data"
  export XDG_CACHE_HOME="$cleanHome/cache"
  export XDG_RUNTIME_DIR="$cleanHome/run"
  export QT_QPA_PLATFORM=offscreen
  timeout 0.4s ${lib.getExe pangu} >/dev/null 2>&1 || true
  test -d "$XDG_CONFIG_HOME/pangu/config"
  test -d "$XDG_CONFIG_HOME/pangu/colors"
  test -d "$XDG_DATA_HOME/pangu"
  test -s "$XDG_CACHE_HOME/pangu/colors.json"
  jq -e '.background and .primary' "$XDG_CACHE_HOME/pangu/colors.json" >/dev/null

  noWePath=${
    lib.makeBinPath (lib.filter (pkg: pkg != pangu.wallpaperEnginePackage) pangu.runtimeInputs)
  }
  weScanOut="$(PATH="$noWePath" bash ${pangu.shellSource}/scripts/wallpaperengine.sh scan "$cleanHome")"
  test -z "$weScanOut"

  touch "$out"
''
