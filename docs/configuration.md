# Configuration

## Home Manager

`programs.pangu.enable` installs the shell and enables its user service,
Hyprland Lua hooks and GTK/Qt palette imports. Each integration can be disabled:

```nix
programs.pangu = {
  enable = true;
  wallpapers = "/srv/wallpapers";
  fonts.enable = false;
  theme = {
    gtk.enable = true;
    qt.enable = true;
    kitty.enable = true;
  };
  systemd.target = "hyprland-session.target";
  hyprland.bindings.enable = false;
};
```

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
    apps = {
      terminal = "kitty";
      browser = "firefox";
      file_manager = "nautilus";
      editor = "kitty nvim";
      shortcuts = [
        { key = "M"; command = "easyeffects"; description = "Apps: EasyEffects"; }
      ];
    };
    keyboard_layout = "se";
    layouts.centered.master_width = 0.5;
    auto_fake_fullscreen = { enable = true; classes = [ "firefox" ]; };
  };
};
```

The first live monitor is used when no primary monitor is specified. Monitor
definitions and workspace-to-monitor assignments stay with the caller. The
preset makes runtime commands available in the user environment for direct
compositor bindings. Additional application shortcuts accept `mods`, defaulting
to `SUPER`, plus `key`, `command` and `description`.

## Persistent settings

Settings remain mutable JSON under `$XDG_CONFIG_HOME/pangu/config`, with state
under `$XDG_DATA_HOME/pangu` and generated files under `$XDG_CACHE_HOME/pangu`.
Defaults use the normal XDG fallback directories. The existing names and file
formats are preserved, so adopting this flake needs no data migration.

```nix
programs.pangu.settings = {
  bar.position = "top";
  system.ocr.spa = false;
};
```

Only specified keys are merged before each service start; sibling settings
survive. GUI edits to overridden keys last until the next service start.
Removing an override leaves its last saved value. Arrays replace arrays.
`pinnedapps` overrides target the data directory, matching the shell's storage.
Unknown file names fail module validation; nested settings follow the QML
schema. Override metadata lets the UI identify Nix-managed values.

`RuntimeDirectory=pangu` contains transient idle and audio configs. The separate
`pangu-session-started` marker survives service restarts to distinguish them
from the first login. The lockscreen's PAM configuration is packaged with QML.

## NixOS prerequisites

The NixOS module has independent `fonts.enable`, `recording.enable`,
`inputAutomation.enable`, `powerProfiles.enable` and `brightness.enable`
switches. They default to true when `programs.pangu.enable` is enabled. Set a
switch to false when you provide that integration differently.

`programs.pangu.package` selects the package used for dependency alignment;
the Home Manager module has its own package option. Use the same package in
both when overriding dependencies. The recording module defaults the system's
recorder package to the shell's recorder package so its privileged helper and
client match. `nvidia-smi` is provided by the installed driver, while optional
EasyEffects and pywal integrations use the session PATH.

For a driver requiring the older NVENC API, select a compatible recorder in
both modules, for example:

```nix
let
  shell = inputs.pangu-shell.packages.${pkgs.stdenv.hostPlatform.system}.pangu.override {
    gpu-screen-recorder = pkgs.gpu-screen-recorder.override { ffmpeg = pkgs.ffmpeg_8; };
  };
in {
  programs.pangu.package = shell;
  home-manager.users.alice.programs.pangu.package = shell;
}
```

Audio, network, Bluetooth, portal and session policies remain with the desktop
configuration. User membership changes take effect on the next login.
