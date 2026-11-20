#!/usr/bin/env bash

set -u

DEFAULT_WORKSHOP_DIR="$HOME/.local/share/Steam/steamapps/workshop/content/431960"
GUI_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Linux Wallpaper Engine"
PREVIEW_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pangu/we_previews"

cmd_scan() {
    command -v linux-wallpaperengine >/dev/null 2>&1 || exit 0
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
            local src_img="$wall/$preview"
            if [[ "$preview" != *'['* && "$preview" != *']'* ]]; then
                src_img="${src_img}[0]"
            fi
            magick "$src_img" "$cached" 2>/dev/null || continue
        fi
        echo "$wall|$cached|$title"
    done
}

cmd_apply() {
    local wall_dir="$1"
    local screen="$2"

    if ! command -v linux-wallpaperengine >/dev/null 2>&1; then
        command -v notify-send >/dev/null 2>&1 && notify-send -e "Wallpaper Engine" "linux-wallpaperengine not found on PATH" -i dialog-error || true
        exit 1
    fi

    local args=(--screen-root "$screen" --bg "$wall_dir")
    local settings_file="$GUI_CONFIG_DIR/settings.json"
    local overrides_file="$GUI_CONFIG_DIR/wallpaper-overrides.json"
    [ -f "$settings_file" ] || settings_file=/dev/null
    [ -f "$overrides_file" ] || overrides_file=/dev/null

    local silent="" volume="" no_automute="" audio_proc="" fps="" disable_mouse="" disable_parallax="" disable_particles="" pause_fs="" scaling="" assets_dir=""
    {
        IFS= read -r -d '' silent || true
        IFS= read -r -d '' volume || true
        IFS= read -r -d '' no_automute || true
        IFS= read -r -d '' audio_proc || true
        IFS= read -r -d '' fps || true
        IFS= read -r -d '' disable_mouse || true
        IFS= read -r -d '' disable_parallax || true
        IFS= read -r -d '' disable_particles || true
        IFS= read -r -d '' pause_fs || true
        IFS= read -r -d '' scaling || true
        IFS= read -r -d '' assets_dir || true
    } < <(
        jq -jn --arg bg "$wall_dir" \
            --slurpfile s "$settings_file" \
            --slurpfile o "$overrides_file" '
            ($s[0] // {}) as $set |
            (($o[0] // {}).overrides[$bg] // {}) as $ov |
            def pick($k): if $ov[$k] != null then $ov[$k] else $set[$k] end;
            def fmt: if . == null then "" else tostring end;
            [
                ($set.silent | fmt),
                (pick("volume") | fmt),
                ($set.noAutomute | fmt),
                (pick("audioProcessing") | fmt),
                ($set.fps | fmt),
                (pick("disableMouse") | fmt),
                (pick("disableParallax") | fmt),
                (pick("disableParticles") | fmt),
                ($set.pauseOnFullscreen | fmt),
                ((if $ov.scaling != null then $ov.scaling else $set.defaultScaling end) | fmt),
                ($set.assetsDir | fmt)
            ] | map(. + "\u0000") | add
        ' 2>/dev/null || true
    )

    if [ "$silent" = "true" ]; then
        args+=(--silent)
    elif [ -n "$volume" ]; then
        args+=(--volume "$volume")
    fi
    [ "$no_automute" = "true" ] && args+=(--noautomute)
    [ "$audio_proc" = "false" ] && args+=(--no-audio-processing)
    [ -n "$fps" ] && args+=(--fps "$fps")
    [ "$disable_mouse" = "true" ] && args+=(--disable-mouse)
    [ "$disable_parallax" = "true" ] && args+=(--disable-parallax)
    [ "$disable_particles" = "true" ] && args+=(--disable-particles)
    [ "$pause_fs" = "false" ] && args+=(--no-fullscreen-pause)
    if [ -n "$scaling" ] && [ "$scaling" != "default" ]; then
        args+=(--scaling "$scaling")
    fi

    if [ -z "$assets_dir" ]; then
        assets_dir="$HOME/.local/share/Steam/steamapps/common/wallpaper_engine/assets"
    fi
    [ -d "$assets_dir" ] && args+=(--assets-dir "$assets_dir")

    local property
    while IFS= read -r -d '' property; do
        args+=(--set-property "$property")
    done < <(python3 "$(dirname -- "${BASH_SOURCE[0]}")/wallpaper_properties.py" arguments "$wall_dir")

    exec linux-wallpaperengine "${args[@]}"
}

case "${1:-}" in
    scan) shift; cmd_scan "$@" ;;
    apply) shift; cmd_apply "$@" ;;
    *) echo "usage: $0 {scan [dir]|apply <dir> <screen>}" >&2; exit 1 ;;
esac
