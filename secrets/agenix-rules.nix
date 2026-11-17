# agenix recipients. Every secret is readable by the admin keys and every host;
# the fleet shares one WiFi network and one operator account, so there is
# nothing to gain from per-host scoping.
#
# Host keys are files in ./host-keys, written by `./deploy bootstrap`.
let
  inventory = import ../inventory.nix;
  readKey = f: builtins.head (builtins.split "\n" (builtins.readFile (./host-keys + "/${f}")));
  hostKeys = map readKey
    (builtins.filter (f: builtins.match ".*\\.pub" f != null)
      (builtins.attrNames (builtins.readDir ./host-keys)));
  everyone = inventory.adminKeys ++ hostKeys;

  # Each Mac's Syncthing key, made by `./deploy bootstrap`. Listed once it
  # exists (rekeying needs every listed file); ./deploy names the one it is
  # creating in AGENIX_NEW_SYNCTHING.
  syncthingHosts = builtins.filter
    (n: builtins.pathExists (./syncthing + "/${n}.key.age") || n == builtins.getEnv "AGENIX_NEW_SYNCTHING")
    (builtins.attrNames inventory.hosts);
in
builtins.listToAttrs (map (n: { name = "syncthing/${n}.key.age"; value.publicKeys = everyone; }) syncthingHosts) //
{
  "wifi.age".publicKeys = everyone;
  "autologin-password.age".publicKeys = everyone;
  "support.age".publicKeys = everyone;
  "rustdesk.age".publicKeys = everyone;
  "nas-password.age".publicKeys = everyone;
  "syncthing-gui.age".publicKeys = everyone;
  "syncthing-peers.age".publicKeys = everyone;
}
