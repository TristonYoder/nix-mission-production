# decklink-config (see decklink-config.cpp). Built against the DeckLink SDK
# headers, which Blackmagic license for redistribution; the copy OBS Studio
# vendors is fetched by pinned commit, since the SDK download itself sits
# behind a registration form. At run time the SDK loads the driver's own
# /Library/Frameworks/DeckLinkAPI.framework, so a newer Desktop Video is fine.
{ lib, stdenv, fetchurl, linkFarm, nlohmann_json }:

let
  obsCommit = "fe1ed7955f300efd17fc59f65938388e43d8bb06"; # SDK 12.0
  sdkFile = name: hash: {
    inherit name;
    path = fetchurl {
      url = "https://raw.githubusercontent.com/obsproject/obs-studio/${obsCommit}/plugins/decklink/mac/decklink-sdk/${name}";
      inherit hash;
    };
  };
  sdk = linkFarm "decklink-sdk-12.0" [
    (sdkFile "DeckLinkAPI.h" "sha256-lFtvhPYA4gTdUpdAinohCSGJxqkHoqzn7WO+WVydf+Y=")
    (sdkFile "DeckLinkAPIConfiguration.h" "sha256-U9/CjV7TT8e7dhruLxKeBV3tWI4hhoMoyz5ERyh9G9M=")
    (sdkFile "DeckLinkAPIDeckControl.h" "sha256-iEg+gp+0kwZjygAV8aZ7kYYd2jh8CrGYBgFUginN8DE=")
    (sdkFile "DeckLinkAPIDiscovery.h" "sha256-7scEMg6I510l3xe1dAwzoK692geLtA+vQx3CMgRlMzk=")
    (sdkFile "DeckLinkAPIDispatch.cpp" "sha256-BRMgMidstPlvShhbs7AnDEdXTqGImtdwccSmnNc0NkM=")
    (sdkFile "DeckLinkAPIModes.h" "sha256-VVFopgZvN8w7xUCzSlS7QSeumgQ0FnM5Czv6uiSBr08=")
    (sdkFile "DeckLinkAPIStreaming.h" "sha256-VEOxT7EB5GOFQbzCCK8oCe9UrXdbfhQh9z8xJz/H7fE=")
    (sdkFile "DeckLinkAPITypes.h" "sha256-7D8NfnizZqC8AkWy98UiXIpOCrAvPiblgdNX1ICqvHA=")
    (sdkFile "DeckLinkAPIVersion.h" "sha256-2zL2vkGIRyrp/QIVJyZdTXiTv3fncvTNTPj8t1HPH28=")
  ];
in
stdenv.mkDerivation {
  pname = "decklink-config";
  version = "1";

  src = ./decklink-config.cpp;
  dontUnpack = true;

  buildInputs = [ nlohmann_json ];

  buildPhase = ''
    runHook preBuild
    $CXX -std=c++17 -O2 -Wall -I${sdk} \
      $src ${sdk}/DeckLinkAPIDispatch.cpp \
      -framework CoreFoundation -o decklink-config
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 decklink-config $out/bin/decklink-config
    runHook postInstall
  '';

  meta = {
    description = "Dump and apply Blackmagic DeckLink card settings";
    platforms = lib.platforms.darwin;
    mainProgram = "decklink-config";
  };
}
