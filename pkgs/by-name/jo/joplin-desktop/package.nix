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
    hash = "sha256-fAjeZk4xG4rzmxxLriG4Ofjmmany6KDSttqx4VpPWOI=";
    postFetch = ''
      # Remove not needed subpackages to reduce dependencies that need to be fetched/built
      # and would require unneccessary complexity to fix.
      rm -r $out/packages/{app-cli,app-clipper,app-mobile,doc-builder,onenote-converter,server}
    '';
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
  ]
  # ++ lib.optionals stdenv.hostPlatform.isDarwin [ xcbuild ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ copyDesktopItems ];

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = 1;
    # Disable scripts for now, so that yarnBerryConfigHook does not try to build anything
    # before we can patchShebangs additional paths (see buildPhase).
    # https://github.com/NixOS/nixpkgs/blob/3cd051861c41df675cee20153bfd7befee120a98/pkgs/by-name/ya/yarn-berry/fetcher/yarn-berry-config-hook.sh#L83
    YARN_ENABLE_SCRIPTS = 0;
  };

  postPatch = ''
    # Add vendored lock file due to removed subpackages
    cp ${./yarn.lock} ./yarn.lock
    # Fix build error due to removal of app-mobile
    sed -i '/app-mobile\//d' packages/tools/gulp/tasks/buildScriptIndexes.js
    # Don't build the default plugins, would require networking. We build them separately. (TODO)
    sed -i "/'buildDefaultPlugins',/d" packages/app-desktop/gulpfile.ts
  '';

  buildPhase = ''
    runHook preBuild

    unset YARN_ENABLE_SCRIPTS

    for node_modules in packages/*/node_modules; do
      patchShebangs $node_modules
    done

    YARN_IGNORE_PATH=1 yarn install --inline-builds

    cd packages/app-desktop
    # Fix for Linux build
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
