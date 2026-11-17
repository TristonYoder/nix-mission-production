# Syncthing on every Mac with Resolume, running as the operator from login.
# Configure folders and devices in its web UI at http://127.0.0.1:8384 on the
# Mac; that config lives in ~/Library/Application Support/Syncthing.
#
# From nixpkgs rather than the Homebrew cask: the Nix build has Syncthing's
# self-upgrade compiled out, so it only changes when a deploy changes it.
{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (lib.elem "resolume" config.production.apps) {
    environment.systemPackages = [ pkgs.syncthing ];

    launchd.user.agents.syncthing.serviceConfig = {
      ProgramArguments = [ "${pkgs.syncthing}/bin/syncthing" "serve" "--no-browser" ];
      EnvironmentVariables.STNOUPGRADE = "1";
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
    };
  };
}
