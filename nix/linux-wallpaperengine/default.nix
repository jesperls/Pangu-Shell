{ linux-wallpaperengine }:
linux-wallpaperengine.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./web-texture.patch
    ./web-shutdown.patch
  ];
})
