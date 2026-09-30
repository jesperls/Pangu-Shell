# Pangu Shell

A standalone Quickshell desktop shell for Hyprland: bar, launcher, dashboard,
notifications, wallpaper picker, lockscreen, screenshot and recording tools,
clipboard, notes, macros, idle control and desktop palettes.

## Add to a Hyprland NixOS configuration

The integration uses Hyprland's Lua configuration API. Use a Lua-capable
Hyprland and a Home Manager revision with `configType = "lua"`; the lock file
pins the tested versions. Older Hyprlang-only releases are not supported.
Pangu leaves your monitor configuration, application choices and desktop rules
with your existing configuration unless you enable its desktop preset.

Add this input (after publishing the repository):

```nix
inputs.pangu-shell = {
  url = "github:jesperls/Pangu-Shell";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.follows = "home-manager";
};
```

Import the system module and the Home Manager module alongside your existing
Hyprland configuration:

```nix
{ inputs, ... }:
{
  imports = [ inputs.pangu-shell.nixosModules.default ];
  programs.pangu = {
    enable = true;
    users = [ "alice" ];
  };

  home-manager.users.alice = {
    imports = [ inputs.pangu-shell.homeManagerModules.default ];
    programs.pangu = {
      enable = true;
      fonts.enable = false; # The system module installs the fonts.
    };
    wayland.windowManager.hyprland = {
      enable = true;
      configType = "lua";
    };
  };
}
```

No overlay or `extraSpecialArgs` is required for these modules. They build with
the caller's package set, including any dependency overrides. The optional
`overlays.default` supplies `pkgs.pangu` and `pkgs.ttf-phosphor-icons`.

The system module provides fonts, the privileged recording helper, ydotool,
power profiles and I2C brightness access. Your desktop must also supply its
Hyprland session, portals, PipeWire, NetworkManager and Bluetooth services for
those features. The `users` list grants access to the system helpers; it does
not select which users run the shell.

The Home Manager module installs Pangu, starts `pangu.service` with
`hyprland-session.target`, loads its Lua integration and connects GTK/Qt
palettes. Default shell shortcuts are Super alone for launcher, Super+A for
dashboard, Super+Tab for overview, Super+I for settings and Super+L for lock.
Set `programs.pangu.hyprland.bindings.enable = false` to supply your own.

See [configuration](docs/configuration.md) for feature switches, the optional
desktop preset, persistent settings and recording overrides.

## Local checkout

Before publishing, consume a committed local checkout:

```nix
inputs.pangu-shell = {
  url = "git+file:///home/alice/Source/Pangu-Shell";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.follows = "home-manager";
};
```

Commit Pangu edits, then run `nix flake update pangu-shell` in the consuming
configuration. Its lock file pins a Git revision, so editing the Pangu checkout
alone does not update the installed package. The absolute local URL works on
the machine containing that checkout; use the GitHub URL for other machines
after publishing. For a temporary development build, use
`nix build --override-input pangu-shell /path/to/Pangu-Shell .#pangu` in the
consumer; this leaves its lock file unchanged.

## Build and develop

```sh
nix build
nix flake check
nix run . -- help
```

For live development, stop the installed shell and start the checkout runner:

```sh
systemctl --user stop pangu.service
nix run .#dev
```

The runner prepares shaders and uses the packaged runtime environment with
the checkout's QML. Start the installed service again after exiting the runner.
See [development](docs/development.md) for structure, tests and debugging.
