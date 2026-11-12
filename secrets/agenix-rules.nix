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
in
{
  "wifi.age".publicKeys = everyone;
  "autologin-password.age".publicKeys = everyone;
  "support.age".publicKeys = everyone;
}
