{
  lib,
  buildEnv,
  stdenvNoCC,
  writeShellApplication,

  quickshell,

  kdePackages,
  qt6,

  aria2,
  bash,
  bluez,
  brightnessctl,
  cava,
  coreutils,
  curl,
  ddcutil,
  ffmpeg,
  findutils,
  gawk,
  glib,
  gtk3,
  gnugrep,
  gnused,
  gpu-screen-recorder,
  grim,
  headsetcontrol,
  hypridle,
  hyprpicker,
  imagemagick,
  inetutils,
  jq,
  kitty,
  libnotify,
  libqalculate,
  linux-wallpaperengine,
  lua,
  matugen,
  mpv,
  mpvpaper,
  networkmanager,
  networkmanagerapplet,
  nodejs,
  playerctl,
  power-profiles-daemon,
  procps,
  python3,
  slurp,
  socat,
  swappy,
  systemd,
  tesseract,
  tmux,
  wireplumber,
  wl-clipboard,
  wlsunset,
  wtype,
  xvfb-run,
  xdg-terminal-exec,
  xdg-user-dirs,
  xdg-utils,
  zbar,
  zenity,
  ydotool,
  yt-dlp,

  version ? "1.1.5",
  ocrLanguages ? [
    "eng"
    "spa"
    "lat"
    "jpn"
    "chi_sim"
    "chi_tra"
    "kor"
  ],
}:

let
  qmlEnv = buildEnv {
    name = "pangu-qml";
    paths = [
      kdePackages.qtmultimedia
      kdePackages.syntax-highlighting
      qt6.qtdeclarative
      qt6.qtimageformats
      qt6.qtsvg
    ];
    pathsToLink = [
      "/lib/qt-6/qml"
      "/lib/qt-6/plugins"
    ];
  };

  src = stdenvNoCC.mkDerivation {
    name = "pangu-shell";
    src = lib.cleanSourceWith {
      src = ../../shell;
      filter =
        name: type:
        lib.cleanSourceFilter name type && baseNameOf name != "__pycache__" && !lib.hasSuffix ".pyc" name;
    };

    nativeBuildInputs = [
      bash
      python3
      nodejs
      lua
      quickshell
      gtk3
      xvfb-run
      jq
      qt6.qtdeclarative # qmllint
      qt6.qtshadertools
    ];

    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      while IFS= read -r -d $'\0' shader; do
        qsb --qt6 "$shader" -o "$shader.qsb"
      done < <(find . \( -name '*.frag' -o -name '*.vert' \) -print0)
      runHook postBuild
    '';
    dontWrapQtApps = true; # qtdeclarative is here for qmllint only

    doCheck = true;
    checkPhase = ''
      runHook preCheck

      export QML2_IMPORT_PATH="${qmlEnv}/lib/qt-6/qml''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
      export QML_IMPORT_PATH="$QML2_IMPORT_PATH"
      export QT_PLUGIN_PATH="${qmlEnv}/lib/qt-6/plugins''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"

      node tests/test_services.js
      PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
      python3 -m compileall -q scripts
      find scripts -type d -name __pycache__ -exec rm -rf {} +
      while IFS= read -r -d $'\0' script; do
        bash -n "$script"
      done < <(find . -name '*.sh' -print0)

      command -v qmllint >/dev/null || { echo "qmllint not on PATH" >&2; exit 1; }

      find . -name '*.qml' -exec qmllint {} + >qmllint.log 2>&1 || true
      if grep -F '[syntax]' qmllint.log; then
        echo "pangu: QML syntax errors above" >&2
        exit 1
      fi
      rm -f qmllint.log

      runHook postCheck
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r . "$out"
      rm -rf "$out/tests"
      chmod -R u+w "$out"
      chmod +x "$out"/scripts/*
      patchShebangs "$out/scripts"
      runHook postInstall
    '';
  };

  runtimeInputs = [
    quickshell

    aria2
    bash
    bluez
    brightnessctl
    cava
    coreutils
    curl
    ddcutil
    ffmpeg
    findutils
    gawk
    glib # gsettings
    gtk3 # gtk-launch
    gnugrep
    gnused
    (gpu-screen-recorder.override { wrapperDir = "/run/wrappers/bin"; }) # execs the setcap gsr-kms-server for promptless capture
    grim
    headsetcontrol
    hypridle
    hyprpicker
    imagemagick
    inetutils # hostname
    jq
    kitty # the dashboard's tmux tab opens sessions in it
    libnotify
    libqalculate
    linux-wallpaperengine
    matugen
    mpv
    mpvpaper
    networkmanager
    networkmanagerapplet # nm-connection-editor for the wifi panel
    power-profiles-daemon
    playerctl
    procps # pgrep/pkill
    python3
    slurp
    socat # mpv IPC sockets for animated wallpapers
    swappy
    systemd # systemctl, loginctl
    (tesseract.override { enableLanguages = ocrLanguages; })
    tmux # the dashboard's tmux tab drives real sessions
    wireplumber
    wl-clipboard
    wlsunset
    wtype
    xdg-terminal-exec
    xdg-user-dirs
    xdg-utils
    zbar
    zenity
    ydotool
    yt-dlp
  ];
in
writeShellApplication {
  name = "pangu";

  runtimeInputs = [ ]; # captured into PANGU_USER_PATH below before prepending internal tools

  text = ''
    export PANGU_USER_PATH="''${PATH:-}"
    export PANGU_USER_QT_PLUGIN_PATH="''${QT_PLUGIN_PATH-__UNSET__}"
    export PANGU_USER_QML2_IMPORT_PATH="''${QML2_IMPORT_PATH-__UNSET__}"
    export PANGU_USER_QML_IMPORT_PATH="''${QML_IMPORT_PATH-__UNSET__}"
    export PATH="${lib.makeBinPath runtimeInputs}''${PATH:+:$PATH}"

    shellRoot="''${PANGU_SHELL_DIR:-${src}}"
    version=${lib.escapeShellArg version}
    export PANGU_VERSION="$version"

    pangu_bin="$(dirname -- "$(readlink -f -- "$0")")"
    export PATH="$pangu_bin''${PATH:+:$PATH}" # hypridle invokes pangu through PATH

    export QML2_IMPORT_PATH="${qmlEnv}/lib/qt-6/qml''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
    export QML_IMPORT_PATH="$QML2_IMPORT_PATH"
    export QT_PLUGIN_PATH="${qmlEnv}/lib/qt-6/plugins''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"

    if [ -d /run/wrappers/bin ]; then
      export PATH="/run/wrappers/bin:$PATH" # prefer setcap gpu-screen-recorder wrapper
    fi
  ''
  + builtins.readFile ./cli.sh;

  passthru = {
    inherit runtimeInputs qmlEnv;
    shellSource = src;
    hyprlandSource = ../../hyprland/pangu;
    recorderPackage = gpu-screen-recorder;
    wallpaperEnginePackage = linux-wallpaperengine;
    configFiles = builtins.concatLists (
      builtins.filter builtins.isList (
        builtins.split "ConfigFile[^}]*name: \"([a-z]+)\"" (builtins.readFile ../../shell/config/Config.qml)
      )
    );
  };

  meta = {
    description = "Pangu — a Quickshell desktop shell for Hyprland";
    mainProgram = "pangu";
    platforms = lib.platforms.linux;
  };
}
