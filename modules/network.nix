# Static address on the production network. Subnet, router and DNS are shared
# (inventory.nix `network`); each host sets its own `ip`. Hosts without one keep
# DHCP. Only the built-in Ethernet is touched: the Dante adapter stays on DHCP.
{ config, lib, inventory, ... }:

let
  cfg = config.production.network;
  net = inventory.network;
  dns = lib.concatStringsSep " " net.dns;
in
{
  options.production.network = {
    ip = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Static IPv4 address on the production network (null = leave as is).";
    };
    device = lib.mkOption {
      type = lib.types.str;
      default = "en0";
      description = "Interface that carries the production network.";
    };
  };

  config = lib.mkIf (cfg.ip != null) {
    system.activationScripts.postActivation.text = ''
      service=$(networksetup -listnetworkserviceorder | awk -v dev="${cfg.device}" '
        /^\([0-9*]+\)/ { sub(/^\([0-9*]+\) /, ""); name = $0 }
        $0 ~ "Device: " dev "\\)" { print name; exit }')
      if [ -z "$service" ]; then
        echo "warning: no network service on ${cfg.device}; static address not set" >&2
      else
        want="Manual Configuration|IP address: ${cfg.ip}|Subnet mask: ${net.subnetMask}|Router: ${net.router}"
        have=$(networksetup -getinfo "$service" | grep -E '^(Manual|DHCP) Configuration|^IP address|^Subnet mask|^Router' | paste -sd'|' -)
        if [ "$(networksetup -getdnsservers "$service" | paste -sd' ' -)" != "${dns}" ]; then
          networksetup -setdnsservers "$service" ${dns}
        fi
        if [ "$have" != "$want" ]; then
          # Changing the address can drop the SSH session running this deploy,
          # so apply it a few seconds after activation has finished.
          echo "note: $service moves to ${cfg.ip} in a few seconds; reconnect at that address" >&2
          nohup sh -c 'sleep 5; networksetup -setmanual "$0" ${cfg.ip} ${net.subnetMask} ${net.router}' "$service" >/dev/null 2>&1 &
        fi
      fi
    '';
  };
}
