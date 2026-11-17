# Pinned Blackmagic card settings (what Desktop Video Setup shows), applied
# by modules/decklink/decklink-config.cpp:
#   - on every deploy, and
#   - at every boot, which covers the restart after a Desktop Video install or
#     firmware update (those can reset the card).
#
# Settings are keyed by the card's model name, so one block covers every Mac
# with that card and does nothing on Macs without it. Only settings listed
# here are touched; everything else stays as set on the machine.
#
# To read a machine's current settings (to pin them here):
#   ssh missionproduction@<ip> decklink-config dump
# and to see what a deploy would change, without changing it:
#   ssh missionproduction@<ip> decklink-config check /etc/decklink.json
# Setting names are the SDK's bmdDeckLinkConfig* names without the prefix.
# Integer settings take a number or a four-character code ("Hp59" =
# 1080p59.94). Keys starting with "_" in the dump are information only.
{ config, lib, pkgs, ... }:

let
  cfg = config.production.decklink;
  tool = pkgs.callPackage ./decklink/package.nix { };

  value = with lib.types; oneOf [ bool int float str ];
  settings = lib.types.attrsOf value;

  card = lib.types.submodule {
    options = {
      profile = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [
          "OneSubDeviceFullDuplex"
          "OneSubDeviceHalfDuplex"
          "TwoSubDevicesFullDuplex"
          "TwoSubDevicesHalfDuplex"
          "FourSubDevicesHalfDuplex"
        ]);
        default = null;
        description = "How the card's connectors are split into devices. null = leave as is.";
      };
      all = lib.mkOption {
        type = settings;
        default = { };
        description = "Settings for every sub-device (connector) of the card.";
      };
      subDevices = lib.mkOption {
        type = lib.types.attrsOf settings;
        default = { };
        example = { "0" = { DeviceInformationLabel = "Main"; }; };
        description = "Per sub-device settings by index (\"0\" = first), on top of `all`.";
      };
    };
  };

  configFile = pkgs.writeText "decklink.json" (builtins.toJSON (lib.mapAttrs (_: c:
    { inherit (c) all subDevices; } // lib.optionalAttrs (c.profile != null) { inherit (c) profile; }
  ) cfg));

  # At boot the driver can come up after launchd starts us; wait for it.
  bootApply = pkgs.writeShellScript "decklink-apply-at-boot" ''
    for _ in $(seq 1 30); do
      ${lib.getExe tool} dump | grep -q '"profile"' && break
      sleep 2
    done
    exec ${lib.getExe tool} apply ${configFile}
  '';
in
{
  options.production.decklink = lib.mkOption {
    type = lib.types.attrsOf card;
    default = { };
    example = { "DeckLink Duo 2".profile = "FourSubDevicesHalfDuplex"; };
    description = "Blackmagic card settings by model name (as `decklink-config dump` prints it).";
  };

  config = lib.mkIf (cfg != { }) {
    environment.systemPackages = [ tool ];
    environment.etc."decklink.json".source = configFile;

    # After modules/apps.nix's installers, so a fresh driver is in place.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "applying Blackmagic card settings..."
      ${lib.getExe tool} apply ${configFile} || echo "warning: some Blackmagic card settings were not applied" >&2
    '';

    launchd.daemons.decklink-config.serviceConfig = {
      ProgramArguments = [ "${bootApply}" ];
      RunAtLoad = true;
      StandardOutPath = "/var/log/decklink-config.log";
      StandardErrorPath = "/var/log/decklink-config.log";
    };
  };
}
