# Labels ports by network: a daemon renames each port's network service
# after the VLAN or WiFi network (inventory.nix `vlans`) its address falls in, on every network
# change. Only the name changes; the connection isn't touched.
{ config, lib, pkgs, inventory, ... }:

let
  line = v:
    let parts = lib.splitString "/" v.subnet;
    in "${v.name}|${lib.elemAt parts 0}|${lib.elemAt parts 1}";

  labeler = pkgs.writeShellApplication {
    name = "vlan-labels";
    text = ''
      VLANS=${lib.escapeShellArg (lib.concatMapStringsSep "\n" line inventory.vlans)}
    '' + builtins.readFile ./vlan-labels.sh;
  };
in
{
  # Same triggers as the WiFi watchdog (see wifi.nix). Renaming a service
  # rewrites preferences.plist and re-triggers this once; that run is a no-op.
  launchd.daemons.vlan-labels = {
    command = "${labeler}/bin/vlan-labels";
    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 60;
      WatchPaths = [
        "/var/run/resolv.conf"
        "/Library/Preferences/SystemConfiguration/com.apple.network.identification.plist"
        "/Library/Preferences/SystemConfiguration/preferences.plist"
      ];
      StandardOutPath = "/var/log/vlan-labels.log";
      StandardErrorPath = "/var/log/vlan-labels.log";
    };
  };

  # Runs during activation are skipped (see vlan-labels.sh), so label once
  # activation has exited. Detached: the deploy doesn't wait for it.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    nohup /bin/sh -c 'while /usr/bin/pgrep -qf "darwin-system-[^ ]*/activate"; do sleep 2; done
      launchctl kickstart system/${config.launchd.daemons.vlan-labels.serviceConfig.Label}' >/dev/null 2>&1 &
  '';
}
