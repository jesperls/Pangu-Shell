runtimeDir="${XDG_RUNTIME_DIR:-/tmp}/pangu"
brightnessState="$runtimeDir/brightness"

die() {
	echo "pangu: $*" >&2
	exit 1
}

shellPid() {
	local pid
	pid=$(systemctl --user show --property MainPID --value pangu.service 2>/dev/null || true)
	if [ -n "$pid" ] && [ "$pid" != "0" ]; then
		printf '%s' "$pid"
		return 0
	fi
	pgrep -f "$shellRoot/shell.qml" | head -1
}

ipc() {
	local pid
	pid=$(shellPid)
	[ -n "$pid" ] || die "not running"
	qs ipc --pid "$pid" call "$@" >/dev/null
}

percentToUnit() {
	awk -v value="$1" 'BEGIN { printf "%.2f", value / 100 }'
}

listBrightness() {
	bash "$shellRoot/scripts/brightness_list.sh"
}

saveBrightness() {
	local monitor="$1" current
	mkdir -p "$runtimeDir"
	if [ -z "$monitor" ]; then
		listBrightness | cut -d: -f1,2 >"$brightnessState"
		return
	fi
	current=$(listBrightness | grep "^${monitor}:" | cut -d: -f2)
	[ -n "$current" ] || die "no brightness reported for monitor $monitor"
	if [ -f "$brightnessState" ]; then
		grep -v "^${monitor}:" "$brightnessState" >"$brightnessState.tmp" || true
		mv "$brightnessState.tmp" "$brightnessState"
	fi
	printf '%s:%s\n' "$monitor" "$current" >>"$brightnessState"
}

restoreBrightness() {
	local monitor="$1" name value
	[ -f "$brightnessState" ] || die "no saved brightness; run 'pangu brightness -s' first"
	while IFS=: read -r name value; do
		[ -n "$name" ] && [ -n "$value" ] || continue
		[ -z "$monitor" ] || [ "$monitor" = "$name" ] || continue
		ipc brightness set "$(percentToUnit "$value")" "$name"
	done <"$brightnessState"
}

usage() {
	cat <<-EOF
		Pangu $version — desktop shell control

		Usage: pangu [COMMAND]

		  (none)                          Run the shell (this is what the user service execs)
		  run <target>                    Open a shell surface (launcher, dashboard, overview, ...)
		  lock                            Activate the lockscreen
		  reload                          Restart the shell service
		  quit                            Stop the shell service
		  screen on|off                   Toggle DPMS on all outputs
		  suspend                         Suspend the system
		  brightness <0-100> [monitor]    Set brightness
		  brightness +N|-N [monitor]      Adjust brightness relatively
		  brightness -s [monitor]         Save current brightness
		  brightness -r [monitor]         Restore saved brightness
		  brightness -l                   List monitors and their brightness
		  version                         Print the shell version
	EOF
}

case "${1:-}" in
"")
	if command -v gsettings >/dev/null 2>&1; then
		QS_ICON_THEME=$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")
		export QS_ICON_THEME
	fi
	export QT_QPA_PLATFORMTHEME=qt6ct
	unset HL_INITIAL_WORKSPACE_TOKEN
	mkdir -p "$runtimeDir"
	exec qs -p "$shellRoot/shell.qml"
	;;
run)
	[ -n "${2:-}" ] || die "run needs a target"
	ipc pangu run "$2"
	;;
lock)
	ipc pangu run lockscreen
	;;
idle)
	shift
	ipc idle "$@"
	;;
reload)
	systemctl --user restart pangu.service
	;;
quit)
	systemctl --user stop pangu.service
	;;
screen)
	case "${2:-}" in
	on | off) ipc pangu run "screen-$2" ;;
	*) die "usage: pangu screen on|off" ;;
	esac
	;;
suspend)
	systemctl suspend
	;;
brightness)
	case "${2:-}" in
	-l | --list)
		listBrightness
		;;
	-s | --save)
		saveBrightness "${3:-}"
		;;
	-r | --restore)
		restoreBrightness "${3:-}"
		;;
	[+-][0-9]*)
		ipc brightness adjust "$(percentToUnit "$2")" "${3:-}"
		;;
	[0-9]*)
		[ "$2" -le 100 ] || die "brightness must be between 0 and 100"
		monitor="${3:-}"
		case "$monitor" in
		-s | --save)
			monitor=""
			saveBrightness ""
			;;
		esac
		case "${4:-}" in
		-s | --save) saveBrightness "$monitor" ;;
		esac
		ipc brightness set "$(percentToUnit "$2")" "$monitor"
		;;
	*)
		die "usage: pangu brightness <0-100|+N|-N|-s|-r|-l> [monitor]"
		;;
	esac
	;;
version | -v | --version)
	echo "$version"
	;;
help | -h | --help)
	usage
	;;
*)
	die "unknown command '$1' (try 'pangu help')"
	;;
esac
