# Production WiFi. Credentials come from secrets/wifi.age, an env file:
#   SSID=...
#   PSK=...
# Until that secret exists, "join" leaves WiFi alone.
{ config, lib, ... }:

let
  cfg = config.production.wifi;
  secretFile = ../secrets/wifi.age;
  haveSecret = builtins.pathExists secretFile;
  device = "$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')";
in
{
  options.production.wifi.mode = lib.mkOption {
    type = lib.types.enum [ "join" "off" "unmanaged" ];
    default = "join";
    description = ''
      join: add the production network as the top preferred network.
      off: keep the WiFi radio off (e.g. machines that must stay on wired Dante).
      unmanaged: leave WiFi alone.
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.mode == "join" && haveSecret) {
      age.secrets.wifi.file = secretFile;
      system.activationScripts.postActivation.text = ''
        (
          set -a
          # shellcheck source=/dev/null
          . ${config.age.secrets.wifi.path}
          set +a
          dev=${device}
          networksetup -setairportpower "$dev" on
          networksetup -addpreferredwirelessnetworkatindex "$dev" "$SSID" 0 WPA2 "$PSK" >/dev/null
        )
      '';
    })
    (lib.mkIf (cfg.mode == "off") {
      system.activationScripts.postActivation.text = ''
        networksetup -setairportpower ${device} off
      '';
    })
  ];
}
