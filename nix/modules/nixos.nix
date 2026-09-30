{ packageFor }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.pangu;
  feature =
    description:
    lib.mkOption {
      type = lib.types.bool;
      default = true;
      inherit description;
    };
in
{
  options.programs.pangu = {
    enable = lib.mkEnableOption "Pangu's system integration";
    package = lib.mkOption {
      type = lib.types.package;
      default = packageFor pkgs;
      description = "Pangu package whose recorder dependencies the system supports.";
    };
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Existing users granted access to monitor brightness and input automation.";
    };
    fonts.enable = feature "Install Pangu's default fonts system-wide.";
    recording.enable = feature "Enable the privileged GPU recording helper.";
    inputAutomation.enable = feature "Enable ydotool input automation.";
    powerProfiles.enable = feature "Enable the power profile service.";
    brightness.enable = feature "Enable I2C access for external-monitor brightness.";
  };
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf cfg.fonts.enable { fonts.packages = import ../fonts.nix { inherit pkgs; }; })
      (lib.mkIf cfg.recording.enable {
        programs.gpu-screen-recorder.enable = true;
        programs.gpu-screen-recorder.package = lib.mkDefault cfg.package.recorderPackage;
      })
      (lib.mkIf cfg.inputAutomation.enable { programs.ydotool.enable = true; })
      (lib.mkIf cfg.powerProfiles.enable { services.power-profiles-daemon.enable = true; })
      (lib.mkIf cfg.brightness.enable {
        hardware.i2c.enable = true;
        services.udev.packages = [ pkgs.brightnessctl ];
      })
      {
        users.users = lib.genAttrs cfg.users (_: {
          extraGroups = [
            "video"
          ]
          ++ lib.optional cfg.brightness.enable "i2c"
          ++ lib.optional cfg.inputAutomation.enable config.programs.ydotool.group;
        });
      }
    ]
  );
}
