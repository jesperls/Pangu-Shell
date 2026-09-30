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
  disabled = (home { programs.pangu.enable = lib.mkForce false; }).config;
  manual =
    (home {
      programs.pangu.systemd.enable = false;
      programs.pangu.hyprland.enable = false;
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
  home-manager =
    assert valid plain && valid preset && valid overrides && valid disabled && valid manual;
    assert !invalid.success;
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
    assert nixos.programs.gpu-screen-recorder.package == nixos.programs.pangu.package.recorderPackage;
    assert nixos.programs.ydotool.enable && nixos.services.power-profiles-daemon.enable;
    assert nixos.hardware.i2c.enable;
    assert builtins.elem "i2c" nixos.users.users.pangu-test.extraGroups;
    assert builtins.elem nixos.programs.ydotool.group nixos.users.users.pangu-test.extraGroups;
    assert !nixosDisabled.programs.gpu-screen-recorder.enable;
    assert !nixosDisabled.programs.ydotool.enable;
    pkgs.runCommand "pangu-nixos-check" { } ''touch "$out"'';

  hyprland = pkgs.runCommand "pangu-hyprland-check" { nativeBuildInputs = [ pkgs.lua ]; } ''
    lua ${../tests/hyprland.lua} ${../hyprland/pangu}
    lua ${../tests/integration.lua} ${../hyprland/pangu}
    touch "$out"
  '';

  runtime = import ./runtime-check.nix { inherit lib pkgs pangu; };
}
