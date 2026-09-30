{
  description = "Pangu, a standalone Quickshell desktop shell for Hyprland";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" ];
      forAllSystems = lib.genAttrs systems;
      version = self.shortRev or self.dirtyShortRev or "dev";
      packageFor = pkgs: pkgs.callPackage ./nix/package { inherit version; };
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      overlays.default = final: prev: {
        pangu = packageFor final;
        ttf-phosphor-icons = final.callPackage ./nix/phosphor-icons { };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          pangu = packageFor pkgs;
          default = self.packages.${system}.pangu;
          ttf-phosphor-icons = pkgs.callPackage ./nix/phosphor-icons { };
        }
      );

      homeManagerModules.default = import ./nix/modules/home-manager.nix { inherit packageFor; };
      nixosModules.default = import ./nix/modules/nixos.nix { inherit packageFor; };

      checks = forAllSystems (
        system:
        import ./nix/checks.nix {
          inherit lib self home-manager;
          pkgs = pkgsFor system;
          pangu = self.packages.${system}.pangu;
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);

      apps = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          pangu = self.packages.${system}.pangu;
          runner = pkgs.writeShellApplication {
            name = "pangu-dev";
            runtimeInputs = pangu.runtimeInputs ++ [
              pangu
              pkgs.qt6.qtshadertools
            ];
            text = builtins.readFile ./scripts/dev.sh;
          };
        in
        {
          default = {
            type = "app";
            program = lib.getExe pangu;
            meta.description = "Run the Pangu shell";
          };
          dev = {
            type = "app";
            program = lib.getExe runner;
            meta.description = "Run Pangu from a development checkout";
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          pangu = self.packages.${system}.pangu;
        in
        {
          default = pkgs.mkShell {
            packages = pangu.runtimeInputs ++ [
              pangu
              pkgs.nodejs
              pkgs.lua
              pkgs.xvfb-run
              pkgs.qt6.qtdeclarative
              pkgs.qt6.qtshadertools
              pkgs.nixfmt-tree
            ];
            QML2_IMPORT_PATH = "${pangu.qmlEnv}/lib/qt-6/qml";
            QML_IMPORT_PATH = "${pangu.qmlEnv}/lib/qt-6/qml";
            QT_PLUGIN_PATH = "${pangu.qmlEnv}/lib/qt-6/plugins";
          };
        }
      );
    };
}
