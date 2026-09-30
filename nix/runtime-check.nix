{
  lib,
  pkgs,
  pangu,
}:
pkgs.runCommand "pangu-runtime-check" { nativeBuildInputs = [ pkgs.bash ]; } ''
  export PATH=${lib.makeBinPath pangu.runtimeInputs}
  for cmd in qs bash find python3 jq grep sed awk pkill pgrep hypridle gtk-launch \
    xdg-terminal-exec matugen mpvpaper grim slurp wl-copy ddcutil brightnessctl \
    tesseract zbarimg swappy notify-send wtype mpv ydotool \
    nmcli bluetoothctl hyprpicker playerctl gpu-screen-recorder tmux; do
    command -v "$cmd" >/dev/null || { echo "Pangu runtime is missing: $cmd" >&2; exit 1; }
  done
  ${lib.getExe pangu} help >/dev/null
  touch "$out"
''
