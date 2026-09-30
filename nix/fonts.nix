{ pkgs }:
with pkgs;
[
  (pkgs.callPackage ./phosphor-icons { })
  inter
  roboto
  roboto-mono
  terminus_font_ttf
  nerd-fonts.symbols-only
  (nerd-fonts.iosevka.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      find $out -name '*.ttf' ! -name 'IosevkaNerdFontMono-*' -delete
    '';
  }))
]
