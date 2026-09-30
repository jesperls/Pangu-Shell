# Pangu Shell

A standalone desktop shell for Hyprland, built with Quickshell and packaged
with Nix. Pangu brings the bar, launcher, dashboard and desktop tools into one
place, with settings you can change from the shell itself.

## Features

- **Desktop:** configurable bar and dock, workspace overview, system tray with
  persistent icon overflow and notifications.
- **Launcher and dashboard:** application search, media controls, calendar,
  weather and system metrics.
- **System controls:** audio, Wi-Fi, Bluetooth, brightness, power profiles and
  idle control.
- **Personalization:** landscape wallpaper previews, adjustable gallery density,
  symlinked wallpaper collections, slideshows, color schemes and palettes
  for GTK, Qt and Kitty.
- **Capture:** screenshots, OCR and QR scanning with a shared frozen-screen
  selector, screen recording and replay capture.
- **Utilities:** clipboard history, notes, macros, lockscreen and power menu.

## Requirements

The Nix integration requires a Hyprland version with the Lua configuration API
and a Home Manager version that supports `configType = "lua"`. The revisions
in [flake.lock](flake.lock) are the tested combination.

Start with a working Hyprland session. Audio needs PipeWire; the network and
Bluetooth controls need NetworkManager and Bluetooth services. Desktop portals
belong in your system configuration too.

## Install on NixOS

These examples assume Home Manager is already integrated into your NixOS flake.

Add Pangu to your flake inputs:

```nix
inputs.pangu-shell = {
  url = "github:jesperls/Pangu-Shell";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.follows = "home-manager";
};
```

Then add the modules to your NixOS configuration. Replace `alice` with your
existing username:

```nix
{ inputs, ... }:
{
  imports = [ inputs.pangu-shell.nixosModules.default ];

  programs.hyprland.enable = true;
  programs.pangu = {
    enable = true;
    users = [ "alice" ];
  };

  home-manager.users.alice = {
    imports = [ inputs.pangu-shell.homeManagerModules.default ];

    programs.pangu = {
      enable = true;
      fonts.enable = false; # The NixOS module installs the fonts.
    };

    wayland.windowManager.hyprland = {
      enable = true;
      configType = "lua";
    };
  };
}
```

Rebuild your configuration and log into Hyprland. Pangu starts with the session
through `pangu.service`. Log out and back in for new group memberships to apply.

The NixOS module provides fonts, recording helpers, input automation, power
profiles and brightness permissions. The Home Manager module installs and
starts the shell, loads its Hyprland integration and connects GTK/Qt palettes.
No overlay or extra module arguments are needed.

To update an installed copy, run `nix flake update pangu-shell` in your NixOS
configuration and rebuild.

## Make it yours

Open Settings with **Super + I** to adjust the shell. Wallpapers default to
`~/Pictures/Wallpapers`. You can also set preferences through Home Manager:

```nix
programs.pangu = {
  wallpapers = "/srv/wallpapers";
  theme.kitty.enable = true;
  settings.bar.position = "top";
};
```

Nix settings are merged when the service starts. Changes made in the UI to a
Nix-managed value last until the next service start.

By default, your existing monitor setup, application bindings and window layout
stay with your Hyprland configuration. For Pangu's desktop bindings, window
rules, animations and layout behavior, enable its optional preset:

```nix
programs.pangu.hyprland.preset.enable = true;
```

See the [configuration guide](docs/configuration.md) for preset customization,
feature switches, persistent settings and recording overrides.

## Shortcuts and commands

| Shortcut | Action |
| --- | --- |
| Super, released on its own | Launcher |
| Super + A | Dashboard |
| Super + Tab | Workspace overview |
| Super + I | Settings |
| Super + L | Lock screen |

Set `programs.pangu.hyprland.bindings.enable = false` to provide your own shell
shortcuts when using the default integration.

```sh
pangu run launcher
pangu run dashboard
pangu lock
pangu reload
pangu help
```

`pangu reload` restarts the installed service. To inspect it, use
`systemctl --user status pangu.service`.

## Develop from a checkout

Run these commands inside an existing Hyprland session:

```sh
git clone https://github.com/jesperls/Pangu-Shell.git
cd Pangu-Shell
```

If the installed service is running, stop it with
`systemctl --user stop pangu.service`. Then start the checkout:

```sh
nix run .#dev
```

The runner compiles shaders and runs the checkout's QML with the packaged
dependencies. Stop it with Ctrl+C; use `systemctl --user start pangu.service`
to return to the installed shell.

To build and check the project:

```sh
nix build
nix fmt -- --ci
nix flake check
```

The [development guide](docs/development.md) covers the source layout, individual
tests, debugging and using a local checkout as a flake input.
