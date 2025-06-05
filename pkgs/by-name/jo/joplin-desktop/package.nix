{
  stdenv,
  nodejs,
  fetchFromGitHub,
  yarn-berry_3,
  python3,
  pkg-config,
  # sqlite,
  pango,
  cairo,
  pixman,
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
    rev = "refs/tags/v${finalAttrs.version}";
    hash = "sha256-DDHUBtIjzeFL/iMaHDniOSLS3Y8Mwcp6BuHc+w/u8Ic=";
  };

  nativeBuildInputs = [
    nodejs
    yarn-berry.yarnBerryConfigHook
    (python3.withPackages(ps: with ps; [ distutils ]))
    pkg-config
    pango
    cairo
    pixman
  ];

  buildInputs = [
    # sqlite
  ];

  missingHashes = ./missing-hashes.json;

  offlineCache = yarn-berry.fetchYarnBerryDeps {
    inherit (finalAttrs) src missingHashes;
    hash = "sha256-obMlkN2Ajq7UetAPTdRjzT/BkJSYQP74uP35dowWprA=";
  };

  postPatch = ''
    sed -i '/postinstall/d' package.json
  '';

  buildPhase = ''
    runHook preBuild

    cd packages/app-desktop
    mkdir dist && touch dist/AppImage
    yarn run dist --dir # --config.asar=false

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/joplin-desktop"
    cp -r dist/*unpacked "$out/share/joplin-desktop"

    runHook postInstall
  '';
})
