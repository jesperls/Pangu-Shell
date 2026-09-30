{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ttf-phosphor-icons";
  version = "2.1.2";

  src = fetchzip {
    url = "https://github.com/phosphor-icons/web/archive/refs/tags/v${finalAttrs.version}.zip";
    hash = "sha256-96ivFjm0cBhqDKNB50klM7D3fevt8X9Zzm82KkJKMtU=";
    stripRoot = true;
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 src/*/*.ttf -t $out/share/fonts/truetype
    runHook postInstall
  '';

  meta = {
    description = "Flexible icon family for interfaces, diagrams and presentations";
    homepage = "https://phosphoricons.com";
    platforms = lib.platforms.all;
  };
})
