# System-wide fonts, installed to /Library/Fonts/Nix Fonts so every app and
# user sees them. Inter goes on every Mac; roles add folders of their own
# (see roles/cg.nix and fonts/).
{ config, lib, pkgs, ... }:

let
  # Every .ttf/.otf/.ttc/.dfont under `dir`, subfolders included, flattened
  # into one package nix-darwin can install.
  fontsFromDir = dir:
    pkgs.runCommand "fonts-${baseNameOf (toString dir)}" { } ''
      mkdir -p $out/share/fonts
      find ${dir} -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' -o -iname '*.dfont' \) \
        -exec cp -- {} $out/share/fonts/ \;
    '';
in
{
  options.production.fontDirs = lib.mkOption {
    type = lib.types.listOf lib.types.path;
    default = [ ];
    description = "Repo folders whose font files are installed system-wide.";
  };

  config.fonts.packages =
    [ pkgs.inter ] ++ map fontsFromDir config.production.fontDirs;
}
