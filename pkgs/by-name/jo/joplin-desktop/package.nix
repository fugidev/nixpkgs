{
  lib,
  stdenv,
  nodejs,
  makeDesktopItem,
  copyDesktopItems,
  makeWrapper,
  fetchFromGitHub,
  yarn-berry_3,
  python3,
  pkg-config,
  pango,
  cairo,
  pixman,
  libsecret,
  electron,
  # node-gyp,
}:

let
  yarn-berry = yarn-berry_3;
in

stdenv.mkDerivation (finalAttrs: {
  pname = "joplin-desktop";
  version = "3.3.12";

  src = fetchFromGitHub {
    owner = "laurent22";
    repo = "joplin";
    tag = "v${finalAttrs.version}";
    hash = "sha256-DDHUBtIjzeFL/iMaHDniOSLS3Y8Mwcp6BuHc+w/u8Ic=";
    # postFetch = ''
    #   rm -r $out/packages/{app-mobile,app-clipper,server,doc-builder,onenote-converter}
    # '';
  };

  missingHashes = ./missing-hashes.json;

  offlineCache = yarn-berry.fetchYarnBerryDeps {
    inherit (finalAttrs) src missingHashes postPatch;
    hash = "sha256-3THkd6uGr/813/m+QPOrye32QakSeWDHjBgZBz8RrYw=";
  };

  nativeBuildInputs = [
    nodejs
    yarn-berry.yarn-berry-offline
    yarn-berry.yarnBerryConfigHook
    (python3.withPackages(ps: with ps; [ distutils ]))
    pkg-config
    pango
    cairo
    pixman
    libsecret
    makeWrapper
    # node-gyp
  ]
  # ++ lib.optionals stdenv.hostPlatform.isDarwin [ xcbuild ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ copyDesktopItems ];

  env = {
    YARN_ENABLE_SCRIPTS = 0;
    ELECTRON_SKIP_BINARY_DOWNLOAD = 1;
  };

  postPatch = ''
    rm -r packages/{app-mobile,app-clipper,app-cli,server,doc-builder,onenote-converter}
    cp ${./yarn.lock} yarn.lock
    sed -i "/'buildDefaultPlugins',/d" packages/app-desktop/gulpfile.ts
    # Fix: Build error due to removal of app-mobile
    sed -i '/app-mobile\//d' packages/tools/gulp/tasks/buildScriptIndexes.js
    # sed -i "s/jetify/true/" packages/app-mobile/package.json
  '';

  buildPhase = ''
    runHook preBuild

    unset YARN_ENABLE_SCRIPTS

    patchShebangs packages/app-desktop/node_modules

    # yarn rebuild
    YARN_IGNORE_PATH=1 yarn install --inline-builds

    yarn workspaces foreach \
      --verbose \
      --interlaced \
      --topological \
      --recursive \
      --from @joplin/app-desktop \
      run build
    yarn tsc

    cd packages/app-desktop
    mkdir dist && touch dist/AppImage
    yarn run electron-builder \
      --dir \
      -c.electronDist="${electron.dist}" \
      -c.electronVersion=${electron.version}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      mkdir -p "$out/share/joplin-desktop"
      cp -r dist/*unpacked/* "$out/share/joplin-desktop"

      for file in "$src/Assets/LinuxIcons"/*.png; do
        resolution=$(basename "$file" .png)
        install -Dm644 "$file" "$out/share/icons/hicolor/$resolution/apps/joplin.png"
      done

      makeWrapper ${lib.getExe electron} $out/bin/joplin-desktop \
        --add-flags $out/share/joplin-desktop/resources/app.asar \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=WaylandWindowDecorations --enable-wayland-ime}}" \
        --inherit-argv0
    ''}

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "joplin";
      desktopName = "Joplin";
      exec = "joplin-desktop --no-sandbox %U";
      icon = "joplin";
      comment = "Joplin for Desktop";
      categories = [ "Office" ];
      startupWMClass = "@joplin/app-desktop";
      mimeTypes = [ "x-scheme-handler/joplin" ];
    })
  ];
})
