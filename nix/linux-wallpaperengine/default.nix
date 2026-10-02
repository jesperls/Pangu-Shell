{ linux-wallpaperengine, nodejs }:
linux-wallpaperengine.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./web-texture.patch
    ./web-shutdown.patch
    ./web-properties.patch
  ];
  postBuild = (old.postBuild or "") + ''
    $CXX -std=c++20 -I../src -I../src/External/json/include \
      ${./web-properties-test.cpp} -o web-properties-test
    ./web-properties-test > web-properties-test.js
    ${nodejs}/bin/node ${./web-properties-test.js} web-properties-test.js
  '';
})
