{ packageFor, qs-vpets }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.pangu;
  settings = lib.filterAttrs (_: value: value != { }) cfg.settings;
  hasSettings = settings != { };
  overridePaths =
    prefix: value:
    if builtins.isAttrs value then
      lib.concatLists (lib.mapAttrsToList (name: child: overridePaths (prefix ++ [ name ]) child) value)
    else
      [ (lib.concatStringsSep "." prefix) ];
  overrideMetadata = pkgs.writeText "pangu-nix-overrides.json" (
    builtins.toJSON (overridePaths [ ] settings)
  );
  applySettings = import ../lib/apply-settings.nix {
    inherit pkgs lib settings;
    configDir = "${config.xdg.configHome}/pangu/config";
    dataDir = "${config.xdg.dataHome}/pangu";
  };
  defaults = import ../../hyprland/defaults.nix;
  unknownPresetPaths =
    prefix: schema: user:
    lib.concatLists (
      lib.mapAttrsToList (
        name: value:
        let
          path = prefix ++ [ name ];
        in
        if !(builtins.hasAttr name schema) then
          [ (lib.concatStringsSep "." path) ]
        else if builtins.isAttrs schema.${name} && schema.${name} != { } && builtins.isAttrs value then
          unknownPresetPaths path schema.${name} value
        else
          [ ]
      ) user
    );
  unknownPresetKeys = unknownPresetPaths [ ] defaults cfg.hyprland.preset.settings;
  state = lib.recursiveUpdate defaults cfg.hyprland.preset.settings;
  paletteImport = ''
    @import url("file://${config.xdg.cacheHome}/pangu/gtk.css");
  '';
  qtPalette = ver: {
    Appearance.custom_palette = true;
    Appearance.color_scheme_path = "${config.xdg.configHome}/${ver}/colors/pangu.colors";
  };
in
{
  imports = [ qs-vpets.homeModules.default ];

  options.programs.pangu = {
    enable = lib.mkEnableOption "the Pangu desktop shell";
    package = lib.mkOption {
      type = lib.types.package;
      default =
        let
          base = packageFor pkgs;
        in
        if cfg.wallpaperEngine.enable then
          base
        else
          base.override {
            withWallpaperEngine = false;
            linux-wallpaperengine = null;
          };
      defaultText = lib.literalExpression "packageFor pkgs";
      description = "Pangu package to run.";
    };
    wallpaperEngine.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include the Linux Wallpaper Engine renderer.";
    };
    pets.enable = lib.mkEnableOption "desktop virtual pets (qs-vpets) and the toolbar Sanctuary button";
    wallpapers = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Pictures/Wallpapers";
      description = "Wallpaper library used by the picker.";
    };
    settings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      description = "Per-file overrides merged into mutable JSON before each start.";
    };
    fonts.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Pangu's default fonts for this user.";
    };
    systemd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Start Pangu with the graphical session.";
      };
      target = lib.mkOption {
        type = lib.types.str;
        default = "hyprland-session.target";
        description = "User session target that owns the Pangu service.";
      };
    };
    hyprland = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install and load the Hyprland Lua integration.";
      };
      bindings.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Add launcher, dashboard, overview, settings and lock shortcuts.";
      };
      preset = {
        enable = lib.mkEnableOption "Pangu's complete desktop preset";
        settings = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Overrides for the desktop preset's generated Lua settings.";
        };
      };
    };
    theme = {
      gtk.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Import Pangu's palette into GTK stylesheets.";
      };
      qt.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use Pangu's palette in qt5ct and qt6ct.";
      };
      kitty.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Import Pangu's palette into Kitty.";
      };
      firefox.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Import Pangu's palette into Firefox profiles.";
      };
      spicetify.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Prepare Pangu's Spicetify theme directory.";
      };
    };
  };

  options.programs.firefox.profiles = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config = lib.mkIf (cfg.enable && cfg.theme.firefox.enable) {
          settings."toolkit.legacyUserProfileCustomizations.stylesheets" = lib.mkDefault true;
          userChrome = lib.mkBefore ''@import url("file://${config.xdg.cacheHome}/pangu/firefox.css");'';
          userContent = lib.mkBefore ''@import url("file://${config.xdg.cacheHome}/pangu/firefox.css");'';
        };
      }
    );
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [
          cfg.package
        ]
        ++ lib.optionals cfg.hyprland.preset.enable cfg.package.runtimeInputs;
        systemd.user.tmpfiles.rules = [
          "d ${config.xdg.configHome}/pangu/config 0755 - - -"
          "d ${config.xdg.configHome}/pangu/colors 0755 - - -"
          "d ${config.xdg.dataHome}/pangu 0755 - - -"
          "d ${config.xdg.cacheHome}/pangu 0755 - - -"
        ];
        assertions = [
          {
            assertion = builtins.all (name: builtins.elem name cfg.package.configFiles) (
              builtins.attrNames settings
            );
            message = "programs.pangu.settings contains unknown files; valid files: ${lib.concatStringsSep ", " cfg.package.configFiles}";
          }
          {
            assertion = unknownPresetKeys == [ ];
            message = "programs.pangu.hyprland.preset.settings contains unknown keys: ${lib.concatStringsSep ", " unknownPresetKeys}";
          }
          {
            assertion = !cfg.hyprland.enable || config.wayland.windowManager.hyprland.configType == "lua";
            message = "Pangu's Hyprland integration requires configType = lua and a Lua-capable Hyprland.";
          }
          {
            assertion = !cfg.hyprland.preset.enable || cfg.hyprland.enable;
            message = "Pangu's desktop preset requires its Hyprland integration.";
          }
        ];
      }
      (lib.mkIf cfg.fonts.enable {
        fonts.fontconfig.enable = lib.mkDefault true;
        home.packages = import ../fonts.nix { inherit pkgs; };
      })
      (lib.mkIf cfg.systemd.enable {
        systemd.user.services.pangu = {
          Unit = {
            Description = "Pangu — desktop shell";
            After = [ cfg.systemd.target ];
            BindsTo = [ cfg.systemd.target ];
            PartOf = [ cfg.systemd.target ];
            ConditionEnvironment = "WAYLAND_DISPLAY";
          };
          Service = {
            ExecStart = lib.getExe cfg.package;
            ExecStartPre = lib.optional hasSettings (lib.getExe applySettings);
            Restart = "on-failure";
            RestartSec = 2;
            RuntimeDirectory = "pangu";
            Slice = "session.slice";
            Environment = [
              "PANGU_WALLPAPERS=${cfg.wallpapers}"
              "PANGU_PETS_ENABLE=${if cfg.pets.enable then "1" else "0"}"
            ]
            ++ lib.optional hasSettings "PANGU_NIX_OVERRIDES=${overrideMetadata}";
          };
          Install.WantedBy = [ cfg.systemd.target ];
        };
      })
      (lib.mkIf cfg.pets.enable {
        programs.qs-vpets = {
          enable = lib.mkDefault true;
          systemd = {
            enable = lib.mkDefault cfg.systemd.enable;
            target = lib.mkDefault cfg.systemd.target;
          };
        };
      })
      (lib.mkIf cfg.hyprland.enable {
        wayland.windowManager.hyprland = {
          enable = lib.mkDefault true;
          configType = lib.mkDefault "lua";
          systemd.enable = lib.mkDefault true;
          extraConfig = lib.mkBefore (
            if cfg.hyprland.preset.enable then
              ''
                require("pangu.init")
              ''
            else
              ''
                require("pangu.integration")
                ${lib.optionalString cfg.hyprland.bindings.enable ''require("pangu.bindings")''}
              ''
          );
        };
        xdg.configFile = {
          "hypr/pangu" = {
            source = cfg.package.hyprlandSource;
            recursive = true;
          };
          "hypr/pangu/generated.lua".text = "return ${lib.generators.toLua { } state}\n";
        };
      })
      (lib.mkIf cfg.theme.gtk.enable {
        gtk.enable = lib.mkDefault true;
        gtk.gtk3.extraCss = paletteImport;
        gtk.gtk4.extraCss = paletteImport;
        systemd.user.tmpfiles.rules = [ "f ${config.xdg.cacheHome}/pangu/gtk.css 0644 - - -" ];
      })
      (lib.mkIf cfg.theme.qt.enable {
        qt.enable = lib.mkDefault true;
        qt.platformTheme.name = lib.mkDefault "qtct";
        qt.qt5ctSettings = qtPalette "qt5ct";
        qt.qt6ctSettings = qtPalette "qt6ct";
        systemd.user.tmpfiles.rules = [
          "d ${config.xdg.configHome}/qt5ct/colors 0755 - - -"
          "f ${config.xdg.configHome}/qt5ct/colors/pangu.colors 0644 - - -"
          "d ${config.xdg.configHome}/qt6ct/colors 0755 - - -"
          "f ${config.xdg.configHome}/qt6ct/colors/pangu.colors 0644 - - -"
        ];
      })
      (lib.mkIf cfg.theme.kitty.enable {
        programs.kitty.extraConfig = lib.mkAfter "include ${config.xdg.cacheHome}/pangu/kitty.conf";
        systemd.user.tmpfiles.rules = [ "f ${config.xdg.cacheHome}/pangu/kitty.conf 0644 - - -" ];
      })
      (lib.mkIf cfg.theme.firefox.enable {
        systemd.user.tmpfiles.rules = [ "f ${config.xdg.cacheHome}/pangu/firefox.css 0644 - - -" ];
      })
      (lib.mkIf cfg.theme.spicetify.enable {
        systemd.user.tmpfiles.rules = [
          "d ${config.xdg.configHome}/spicetify/Themes/Pangu 0755 - - -"
          "f ${config.xdg.configHome}/spicetify/Themes/Pangu/color.ini 0644 - - -"
          "f ${config.xdg.configHome}/spicetify/Themes/Pangu/user.css 0644 - - -"
        ];
      })
    ]
  );
}
