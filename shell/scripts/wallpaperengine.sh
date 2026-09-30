#!/usr/bin/env bash

set -u

DEFAULT_WORKSHOP_DIR="$HOME/.local/share/Steam/steamapps/workshop/content/431960"
GUI_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Linux Wallpaper Engine"
PREVIEW_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pangu/we_previews"

cmd_scan() {
    local dir="${1:-}"
    [ -n "$dir" ] || dir="$DEFAULT_WORKSHOP_DIR"
    [ -d "$dir" ] || exit 0
    mkdir -p "$PREVIEW_CACHE_DIR"

    local project wall preview cached title
    for project in "$dir"/*/project.json; do
        [ -f "$project" ] || continue
        wall=$(dirname "$project")

        title=$(jq -r '.title // empty | gsub("[\\n|]"; " ")' "$project" 2>/dev/null)
        [ -n "$title" ] || title=$(basename "$wall")

        preview=$(jq -r '.preview // empty' "$project" 2>/dev/null)
        if [ -z "$preview" ] || [ ! -f "$wall/$preview" ]; then
            preview=""
            for cand in preview.jpg preview.png preview.gif preview.jpeg; do
                if [ -f "$wall/$cand" ]; then
                    preview="$cand"
                    break
                fi
            done
        fi
        [ -n "$preview" ] || continue

        cached="$PREVIEW_CACHE_DIR/$(basename "$wall").jpg"
        if [ ! -f "$cached" ] || [ "$wall/$preview" -nt "$cached" ]; then
            magick "$wall/$preview[0]" "$cached" 2>/dev/null || continue
        fi
        echo "$wall|$cached|$title"
    done
}

gui_setting() {
    jq -r "$1 | if . == null then empty else . end" "$GUI_CONFIG_DIR/settings.json" 2>/dev/null
}

gui_override() {
    jq -r --arg bg "$wall_dir" ".overrides[\$bg]$1 | if . == null then empty else . end" \
        "$GUI_CONFIG_DIR/wallpaper-overrides.json" 2>/dev/null
}

cmd_apply() {
    wall_dir="$1"
    local screen="$2"

    if ! command -v linux-wallpaperengine >/dev/null 2>&1; then
        notify-send -e "Wallpaper Engine" "linux-wallpaperengine not found on PATH" -i dialog-error
        exit 1
    fi

    local args=(--screen-root "$screen" --bg "$wall_dir")

    local volume silent fps scaling assets_dir v
    silent=$(gui_setting '.silent')
    volume=$(gui_override '.volume')
    [ -n "$volume" ] || volume=$(gui_setting '.volume')
    if [ "$silent" = "true" ]; then
        args+=(--silent)
    elif [ -n "$volume" ]; then
        args+=(--volume "$volume")
    fi
    [ "$(gui_setting '.noAutomute')" = "true" ] && args+=(--noautomute)
    v=$(gui_override '.audioProcessing')
    [ -n "$v" ] || v=$(gui_setting '.audioProcessing')
    [ "$v" = "false" ] && args+=(--no-audio-processing)
    fps=$(gui_setting '.fps')
    [ -n "$fps" ] && args+=(--fps "$fps")
    v=$(gui_override '.disableMouse'); [ -n "$v" ] || v=$(gui_setting '.disableMouse')
    [ "$v" = "true" ] && args+=(--disable-mouse)
    v=$(gui_override '.disableParallax'); [ -n "$v" ] || v=$(gui_setting '.disableParallax')
    [ "$v" = "true" ] && args+=(--disable-parallax)
    v=$(gui_override '.disableParticles'); [ -n "$v" ] || v=$(gui_setting '.disableParticles')
    [ "$v" = "true" ] && args+=(--disable-particles)
    [ "$(gui_setting '.pauseOnFullscreen')" = "false" ] && args+=(--no-fullscreen-pause)
    scaling=$(gui_override '.scaling')
    [ -n "$scaling" ] || scaling=$(gui_setting '.defaultScaling')
    if [ -n "$scaling" ] && [ "$scaling" != "default" ]; then
        args+=(--scaling "$scaling")
    fi

    assets_dir=$(gui_setting '.assetsDir')
    if [ -z "$assets_dir" ]; then
        assets_dir="$HOME/.local/share/Steam/steamapps/common/wallpaper_engine/assets"
    fi
    [ -d "$assets_dir" ] && args+=(--assets-dir "$assets_dir")

    while IFS='=' read -r key value; do
        [ -n "$key" ] && args+=(--set-property "$key=$value")
    done < <(jq -r --arg bg "$wall_dir" \
        '.overrides[$bg].customProperties // {} | to_entries[] | "\(.key)=\(.value)"' \
        "$GUI_CONFIG_DIR/wallpaper-overrides.json" 2>/dev/null)

    exec linux-wallpaperengine "${args[@]}"
}

case "${1:-}" in
    scan) shift; cmd_scan "$@" ;;
    apply) shift; cmd_apply "$@" ;;
    *) echo "usage: $0 {scan [dir]|apply <dir> <screen>}" >&2; exit 1 ;;
esac
