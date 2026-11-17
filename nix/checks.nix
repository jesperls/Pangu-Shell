{
  lib,
  pkgs,
  self,
  home-manager,
  pangu,
}:
let
  home =
    extra:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeManagerModules.default
        {
          home.username = "pangu-test";
          home.homeDirectory = "/home/pangu-test";
          home.stateVersion = "26.05";
          programs.pangu.enable = true;
        }
        extra
      ];
    };
  plain = (home { }).config;
  preset = (home { programs.pangu.hyprland.preset.enable = true; }).config;
  overrides =
    (home {
      programs.pangu.settings = {
        system.ocr.eng = true;
        pinnedapps.apps = [ "kitty" ];
        theme = { };
      };
    }).config;
  invalid =
    builtins.tryEval
      (home { programs.pangu.settings.unknownFile.value = true; }).activationPackage.drvPath;
  invalidPreset =
    builtins.tryEval
      (home {
        programs.pangu.hyprland.preset = {
          enable = true;
          settings.unknownPresetKey = true;
        };
      }).activationPackage.drvPath;
  spacedWallpapers =
    (home {
      programs.pangu.wallpapers = "/home/pangu-test/My Wallpapers";
    }).config;
  noWallpaperEngine =
    (home {
      programs.pangu.wallpaperEngine.enable = false;
    }).config;
  withPets =
    (home {
      programs.pangu.pets.enable = true;
    }).config;
  disabled = (home { programs.pangu.enable = lib.mkForce false; }).config;
  manual =
    (home {
      programs.pangu.systemd.enable = false;
      programs.pangu.hyprland.enable = false;
    }).config;
  themedApps =
    (home {
      programs.firefox = {
        enable = true;
        profiles.default = {
          id = 0;
          isDefault = true;
        };
      };
      programs.pangu.theme = {
        firefox.enable = true;
        spicetify.enable = true;
      };
    }).config;
  valid = c: builtins.all (entry: entry.assertion) c.assertions;
  apply = import ./lib/apply-settings.nix {
    inherit pkgs lib;
    configDir = "config with 'quotes' and $dollars";
    dataDir = "data";
    settings = {
      system = {
        idle.lock.timeout = 42;
        list = [ "replacement" ];
      };
      pinnedapps.apps = [ "kitty" ];
    };
  };
  overrideFile = lib.removePrefix "PANGU_NIX_OVERRIDES=" (
    lib.findFirst (entry: lib.hasPrefix "PANGU_NIX_OVERRIDES=" entry)
      (throw "Pangu override metadata is missing")
      overrides.systemd.user.services.pangu.Service.Environment
  );
  system =
    enabled:
    lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.default
        {
          programs.pangu.enable = enabled;
          programs.pangu.users = [ "pangu-test" ];
          users.users.pangu-test.isNormalUser = true;
          system.stateVersion = "26.05";
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
        }
      ];
    };
  nixos = (system true).config;
  nixosDisabled = (system false).config;
in
{
  package = pangu;
  wallpaper-engine =
    pkgs.runCommand "pangu-wallpaper-engine-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.xvfb-run
          pkgs.imagemagick
          pkgs.dbus
        ];
      }
      ''
        export LIBGL_DRIVERS_PATH=${pkgs.mesa}/lib/dri
        export LD_LIBRARY_PATH=${pkgs.mesa}/lib
        dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- \
          xvfb-run -a -s "-screen 0 320x240x24 -nolisten tcp" \
          python3 ${./linux-wallpaperengine/test-rendering.py} ${lib.getExe pangu.wallpaperEnginePackage}
        touch "$out"
      '';
  home-manager =
    assert
      valid plain
      && valid preset
      && valid overrides
      && valid disabled
      && valid manual
      && valid spacedWallpapers
      && valid noWallpaperEngine
      && valid withPets
      && valid themedApps;
    assert noWallpaperEngine.programs.pangu.package.wallpaperEnginePackage == null;
    assert
      !(builtins.elem pangu.wallpaperEnginePackage noWallpaperEngine.programs.pangu.package.runtimeInputs);
    assert !plain.programs.qs-vpets.enable && !(plain.systemd.user.services ? qs-vpets);
    assert builtins.elem "PANGU_PETS_ENABLE=0" plain.systemd.user.services.pangu.Service.Environment;
    assert withPets.programs.qs-vpets.enable && (withPets.systemd.user.services ? qs-vpets);
    assert withPets.systemd.user.services.qs-vpets.Unit.BindsTo == [ "hyprland-session.target" ];
    assert builtins.elem "PANGU_PETS_ENABLE=1" withPets.systemd.user.services.pangu.Service.Environment;
    assert builtins.any (rule: lib.hasInfix "pangu/gtk.css" rule) plain.systemd.user.tmpfiles.rules;
    assert builtins.any (
      rule: lib.hasInfix "qt6ct/colors/pangu.colors" rule
    ) plain.systemd.user.tmpfiles.rules;
    assert
      themedApps.programs.firefox.profiles.default.settings."toolkit.legacyUserProfileCustomizations.stylesheets";
    assert lib.hasInfix "pangu/firefox.css" themedApps.programs.firefox.profiles.default.userChrome;
    assert lib.hasInfix "pangu/firefox.css" themedApps.programs.firefox.profiles.default.userContent;
    assert builtins.any (
      rule: lib.hasInfix "spicetify/Themes/Pangu/color.ini" rule
    ) themedApps.systemd.user.tmpfiles.rules;
    assert !invalid.success && !invalidPreset.success;
    assert builtins.elem "PANGU_WALLPAPERS=/home/pangu-test/My Wallpapers"
      spacedWallpapers.systemd.user.services.pangu.Service.Environment;
    assert plain.systemd.user.services.pangu.Unit.BindsTo == [ "hyprland-session.target" ];
    assert !(disabled.systemd.user.services ? pangu);
    assert !(manual.systemd.user.services ? pangu);
    assert !(manual.xdg.configFile ? "hypr/pangu");
    assert plain.systemd.user.services.pangu.Service.ExecStartPre == [ ];
    assert
      !(builtins.any (
        entry: lib.hasPrefix "PANGU_NIX_OVERRIDES=" entry
      ) plain.systemd.user.services.pangu.Service.Environment);
    assert lib.hasInfix "pangu.integration" plain.wayland.windowManager.hyprland.extraConfig;
    assert !(lib.hasInfix "pangu.init" plain.wayland.windowManager.hyprland.extraConfig);
    assert lib.hasInfix "pangu.init" preset.wayland.windowManager.hyprland.extraConfig;
    assert lib.hasInfix "pangu/gtk.css" plain.gtk.gtk3.extraCss;
    assert plain.qt.qt6ctSettings.Appearance.custom_palette;
    pkgs.runCommand "pangu-home-manager-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.lua
        ];
      }
      ''
        python3 ${../tests/test_shell_settings.py} ${lib.getExe apply}
        python3 - ${lib.escapeShellArg overrideFile} <<'PY'
        import json, sys
        with open(sys.argv[1]) as stream:
            assert json.load(stream) == ["pinnedapps.apps", "system.ocr.eng"]
        PY
        lua ${../tests/hyprland_contract.lua} ${
          pkgs.writeText "generated.lua" preset.xdg.configFile."hypr/pangu/generated.lua".text
        }
        touch "$out"
      '';

  nixos =
    assert nixos.programs.gpu-screen-recorder.enable;
    assert nixos.security.pam.services ? pangu;
    assert nixos.security.polkit.enable;
    assert nixos.programs.gpu-screen-recorder.package == nixos.programs.pangu.package.recorderPackage;
    assert
      nixos.programs.ydotool.enable
      && nixos.services.power-profiles-daemon.enable
      && nixos.services.upower.enable;
    assert nixos.hardware.i2c.enable;
    assert builtins.elem pkgs.brightnessctl nixos.services.udev.packages;
    assert builtins.elem "i2c" nixos.users.users.pangu-test.extraGroups;
    assert builtins.elem nixos.programs.ydotool.group nixos.users.users.pangu-test.extraGroups;
    assert nixos.environment.sessionVariables.YDOTOOL_SOCKET == "/run/ydotoold/socket";
    assert !nixosDisabled.programs.gpu-screen-recorder.enable;
    assert !nixosDisabled.programs.ydotool.enable;
    assert !(nixosDisabled.environment.sessionVariables ? YDOTOOL_SOCKET);
    assert !nixosDisabled.services.upower.enable;
    pkgs.runCommand "pangu-nixos-check" { } ''touch "$out"'';

  hyprland = pkgs.runCommand "pangu-hyprland-check" { nativeBuildInputs = [ pkgs.lua ]; } ''
    lua ${../tests/hyprland.lua} ${../hyprland/pangu}
    lua ${../tests/hyprland_behavior.lua} ${../hyprland/pangu}
    lua ${../tests/integration.lua} ${../hyprland/pangu}
    touch "$out"
  '';

  development = pkgs.runCommand "pangu-development-check" { } ''
    if ${
      self.apps.${pkgs.stdenv.hostPlatform.system}.dev.program
    } /pangu-missing-checkout >runner.log 2>&1; then
      echo "Development runner accepted a missing checkout" >&2
      exit 1
    fi
    grep -F "run from the Pangu checkout" runner.log
    touch "$out"
  '';

  runtime = import ./runtime-check.nix { inherit lib pkgs pangu; };
}
