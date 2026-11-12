# Configuration

## Home Manager

`programs.pangu.enable` installs the shell and enables its user service,
Hyprland Lua hooks and GTK/Qt palette imports. Each integration can be disabled:

```nix
programs.pangu = {
  enable = true;
  wallpapers = "/srv/wallpapers";
  wallpaperEngine.enable = true;
  fonts.enable = false;
  theme = {
    gtk.enable = true;
    qt.enable = true;
    kitty.enable = true;
    firefox.enable = false;
    spicetify.enable = false;
  };
  systemd.target = "hyprland-session.target";
  hyprland.bindings.enable = false;
};
```

Set `wallpaperEngine.enable = false` to omit the `linux-wallpaperengine`
renderer when Steam Workshop wallpapers are not needed.

Set `systemd.enable = false` for manual startup and `hyprland.enable = false`
for manually managed compositor hooks. In that case, load the equivalent
`hyprland/pangu/integration.lua` from your Hyprland Lua configuration and make
the `pangu` module directory discoverable through Lua's package path. A manual
startup does not run the service's settings merge.

The default integration loads generated decorations, macro keybindings,
game-mode workspace rules and shell-window placement. It does not configure
monitors, input, application shortcuts or tiling layouts. Layer namespaces and
the compositor's Lua IPC interface are part of the shell integration contract.

## Desktop preset

`programs.pangu.hyprland.preset.enable = true` opts into the complete desktop
experience: desktop bindings, application/window rules, animation defaults,
centered master layout, workspace layout switching, scratchpad/popout behavior
and automatic fake fullscreen. This takes ownership of those compositor keys.

Override its generated settings through `hyprland.preset.settings`, using the
Lua keys defined in [`hyprland/defaults.nix`](../hyprland/defaults.nix):

```nix
programs.pangu.hyprland.preset = {
  enable = true;
  settings = {
    monitors.primary = "DP-1";
    monitors.primary_workspaces = [ 1 2 3 4 5 ];
    binds.mouse_side_buttons = true;
    scratchpad = { width = 900; height = 700; };
    apps = {
      terminal = "kitty";
      browser = "firefox";
      file_manager = "nautilus";
      editor = "kitty nvim";
      shortcuts = [
        { key = "M"; command = "easyeffects"; description = "Apps: EasyEffects"; }
      ];
      scratchpads = [
        {
          key = "U";
          name = "term";
          command = "kitty --class scratch-term";
          class = "scratch-term";
          width = 1000;
          height = 650;
          description = "Scratchpad: terminal";
        }
      ];
    };
    keyboard_layout = "se";
    layouts.centered.master_width = 0.5;
    auto_fake_fullscreen = { enable = true; classes = [ "firefox" ]; };
  };
};
```

The first live monitor is cached as primary when no primary monitor is
specified; `desc:` prefixes match monitor descriptions. Monitor definitions and
workspace-to-monitor assignments stay with the caller. Preset keys are validated
against `hyprland/defaults.nix`, and Pangu's Hyprland snippet uses `lib.mkBefore`
so user `extraConfig` runs afterward. The preset makes runtime commands
available in the user environment for direct compositor bindings.

`SUPER + S` toggles `special:scratchpad` on the active monitor, moving an open
scratchpad from another monitor in one press and clamping floating windows into
the active monitor's work area. `SUPER + SHIFT + S` stashes the active window
into `special:scratchpad` or restores a scratchpad window to the active regular
workspace, preserving tiled versus floating state. `apps.scratchpads` entries
accept optional `mods` (default `SUPER`), `class`, `width`, `height` and
`description`, plus `key`, `name` and `command` to spawn on first use and toggle
their named special workspace thereafter. Additional `apps.shortcuts` entries
accept `mods` (default `SUPER`), `key`, `command` and `description`. Set
`binds.mouse_side_buttons = true` when mouse buttons `275`/`276`/`277` should
drag, resize and close windows instead of navigating back and forward.

## Persistent settings

Settings remain mutable JSON under `$XDG_CONFIG_HOME/pangu/config`, with state
under `$XDG_DATA_HOME/pangu` and generated files under `$XDG_CACHE_HOME/pangu`.
Defaults use the normal XDG fallback directories. The existing names and file
formats are preserved, so adopting this flake needs no data migration.

```nix
programs.pangu.settings = {
  bar.position = "top";
  bar.trayIconSize = 20;
  bar.traySpacing = 8;
  bar.trayIconStyle = "theme";
  dashboard.wallpaperCardWidth = 160;
  dashboard.wallpaperShowNames = true;
  theme.exports.discord = true;
  system.clipboard.maxItems = 200;
  system.audio.overAmplify = false;
  system.ocr.spa = false;
};
```

Only specified keys are merged before each service start; sibling settings
survive. Corrupt JSON files are backed up to `.json.corrupt` with a warning and
rebuilt from `{}` so startup is not blocked. GUI edits to overridden keys last
until the next service start. Removing an override leaves its last saved value.
Arrays replace arrays. `pinnedapps` overrides target the data directory,
matching the shell's storage. Unknown file names fail module validation; nested
settings follow the QML schema. Override metadata lets the UI identify
Nix-managed values. Theme exports (`theme.exports.{gtk,qt,kitty,discord,nvchad,pywal,firefox,spicetify}`),
clipboard history pruning (`system.clipboard.maxItems`), audio volume
over-amplification (`system.audio.overAmplify`), and per-device EasyEffects
preset switching (`system.audio.autoSwitchPresets`) can be configured either
here or in the Settings window.

The Shell settings panel exposes tray icon size (16–32 pixels), spacing
(0–24 pixels) and color style (`theme`, `original` or `monochrome`). `theme`
follows the theme's icon tint setting. Shift-click a tray icon to move it
between the bar and overflow. Right-click the overflow arrow to manage all
icons. These choices persist as app IDs in shell state across restarts and
apply to every monitor; middle-click keeps the application's secondary action.

Wallpaper cards adapt to available space with a preferred width of 100–240
pixels and optional filenames. Both controls are under Shell → Dashboard.
Wallpaper folders accept `~/` paths and symlinked files or directories; cycles
and hidden entries are skipped. If a collection is empty or unavailable, the
browser uses the packaged fallback wallpapers.

For Wallpaper Engine wallpapers, select a card and open **Wallpaper settings**
(the gear button), or right-click the card. The panel reads the wallpaper's
built-in properties and offers switches, sliders, choices, RGB color controls,
and fields for text or file paths.
**Apply** saves the values and restarts that wallpaper on every screen using it;
**Discard** leaves the saved values intact. **Defaults** restores the author's
values in the draft, ready to apply. Wallpapers without built-in properties show
an empty state. Property support depends on the Linux Wallpaper Engine renderer.

Values are saved per wallpaper directory in
`$XDG_CONFIG_HOME/pangu/wallpaper-engine.json`. Existing custom properties from
`Linux Wallpaper Engine/wallpaper-overrides.json` are used until superseded by
Pangu's saved values. The source wallpaper and the other GUI's files are left
intact. These properties are shared across screens using the same wallpaper.

`RuntimeDirectory=pangu` contains transient idle, audio-visualizer and macro
sound-detector configs. Recorded or imported macro audio trigger samples live
under `$XDG_DATA_HOME/pangu/macro-sounds`. The separate
`pangu-session-started` marker survives service restarts to distinguish them
from the first login. The wrapper captures the user's clean session `PATH` and
Qt/QML search paths before adding internal runtime dependencies so launched
applications inherit the user environment without wrapper leakage.

## NixOS prerequisites

Enabling `programs.pangu.enable` registers `security.pam.services.pangu = { };`
and `security.polkit.enable` by default so the lockscreen honors system PAM
policies such as `fprintd`, `u2f` and `faillock` (when `/etc/pam.d/pangu` is
absent, the lockscreen probes `/etc/pam.d/hyprlock` and `/etc/pam.d/login`
before falling back to the PAM configuration packaged with QML). The brightness
integration installs backlight udev rules, enables I2C access and grants listed
`users` the `video` and `i2c` groups when `brightness.enable` is true.

The NixOS module has independent `fonts.enable`, `recording.enable`,
`inputAutomation.enable`, `powerProfiles.enable`, `upower.enable` and
`brightness.enable` switches. They default to true when `programs.pangu.enable`
is enabled. Set a switch to false when you provide that integration differently.

`programs.pangu.package` selects the package used for dependency alignment;
the Home Manager module has its own package option. Use the same package in
both when overriding dependencies. The recording module defaults the system's
recorder package to the shell's recorder package so its privileged helper and
client match. `nvidia-smi` is provided by the installed driver, while optional
EasyEffects and pywal integrations use the session PATH.

When overriding a bundled dependency such as `gpu-screen-recorder`, select the
same package in both modules:

```nix
let
  shell = inputs.pangu-shell.packages.${pkgs.stdenv.hostPlatform.system}.pangu.override {
    gpu-screen-recorder = customRecorder;
  };
in {
  programs.pangu.package = shell;
  home-manager.users.alice.programs.pangu.package = shell;
}
```

Audio, network, Bluetooth, portal and session policies remain with the desktop
configuration. User membership changes take effect on the next login.
