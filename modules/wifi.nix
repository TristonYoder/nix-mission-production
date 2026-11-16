# Production WiFi. Credentials come from secrets/wifi.age, an env file:
#   SSID=...
#   PSK=...
# Until that secret exists, the network isn't added (the watchdog still runs).
{ config, lib, pkgs, ... }:

let
  cfg = config.production.wifi;
  secretFile = ../secrets/wifi.age;
  haveSecret = builtins.pathExists secretFile;
  device = "$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')";

  watchdog = pkgs.writeShellApplication {
    name = "wifi-watchdog";
    text = ''
      TARGETS=${lib.escapeShellArg (lib.concatStringsSep " " cfg.probeHosts)}
    '' + builtins.readFile ./wifi-watchdog.sh;
  };
in
{
  options.production.wifi = {
    mode = lib.mkOption {
      type = lib.types.enum [ "auto" "join" "off" "unmanaged" ];
      default = "auto";
      description = ''
        auto: like join, plus a watchdog that turns WiFi off while a wired port
          has internet and back on as soon as none does.
        join: add the production network as the top preferred network, WiFi on.
        off: keep the WiFi radio off (e.g. machines that must stay on wired Dante).
        unmanaged: leave WiFi alone.
      '';
    };
    probeHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "8.8.8.8" ];
      description = "Pinged through each wired port; any reply means that port has internet.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (lib.elem cfg.mode [ "auto" "join" ] && haveSecret) {
      age.secrets.wifi.file = secretFile;
      system.activationScripts.postActivation.text = ''
        (
          set -a
          # shellcheck source=/dev/null
          . ${config.age.secrets.wifi.path}
          set +a
          dev=${device}
          ${lib.optionalString (cfg.mode == "join") ''networksetup -setairportpower "$dev" on''}
          networksetup -addpreferredwirelessnetworkatindex "$dev" "$SSID" 0 WPA2 "$PSK" >/dev/null
        )
      '';
    })
    (lib.mkIf (cfg.mode == "auto") {
      # Runs on every network change: configd rewrites these whenever a link,
      # address or DNS changes. The interval catches an uplink that dies or
      # comes back without the link itself changing. launchd never runs two
      # at once and spaces runs at least 10s apart.
      # `command` goes through /bin/sh, so deploys don't re-trigger macOS's
      # background-item notification (see wallpaper.nix).
      launchd.daemons.wifi-watchdog = {
        command = "${watchdog}/bin/wifi-watchdog";
        serviceConfig = {
          RunAtLoad = true;
          StartInterval = 30;
          WatchPaths = [
            "/var/run/resolv.conf"
            "/Library/Preferences/SystemConfiguration/com.apple.network.identification.plist"
            "/Library/Preferences/SystemConfiguration/preferences.plist"
          ];
          StandardOutPath = "/var/log/wifi-watchdog.log";
          StandardErrorPath = "/var/log/wifi-watchdog.log";
        };
      };
      system.activationScripts.postActivation.text = ''
        launchctl kickstart system/${config.launchd.daemons.wifi-watchdog.serviceConfig.Label} 2>/dev/null || true
      '';
    })
    (lib.mkIf (cfg.mode == "off") {
      system.activationScripts.postActivation.text = ''
        networksetup -setairportpower "${device}" off
      '';
    })
  ];
}
