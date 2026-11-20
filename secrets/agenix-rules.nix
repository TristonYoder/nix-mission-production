# agenix recipients. Every secret is readable by the admin keys and every host;
# the fleet shares one WiFi network and one operator account, so there is
# nothing to gain from per-host scoping.
#
# Host keys are files in ./host-keys, written by `./deploy bootstrap` (named
# hosts) or by the enrollment PR (generic Macs, .github/workflows/enroll-host.yml).
# ./ci-key.pub is the GitHub Actions key that re-keys for those PRs
# (macos-firstboot/setup-enrollment.sh); delete it and re-key to revoke CI.
let
  inventory = import ../inventory.nix;
  firstLine = p: builtins.head (builtins.split "\n" (builtins.readFile p));
  readKey = f: firstLine (./host-keys + "/${f}");
  hostKeys = map readKey
    (builtins.filter (f: builtins.match ".*\\.pub" f != null)
      (builtins.attrNames (builtins.readDir ./host-keys)));
  ciKeys = if builtins.pathExists ./ci-key.pub then [ (firstLine ./ci-key.pub) ] else [ ];
  everyone = inventory.adminKeys ++ ciKeys ++ hostKeys;

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
