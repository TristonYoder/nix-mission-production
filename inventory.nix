# Single source of truth for the fleet. Adding a machine = one entry under
# `hosts`, then `./deploy bootstrap <name> <address>`.
{
  # The shared operator account. Created by hand in Setup Assistant on each Mac
  # (full name "Mission Production"); its password is never in this repo.
  user = "missionproduction";

  # SSH public keys allowed to deploy (the "known Mac"). Public keys are safe to
  # commit.
  deployKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5JWm3A5tXTCPq8YTua30QH2+Pa/Mz96QC5KJZKdEsz Triston Yoder"
  ];

  # Recipients that can decrypt every secret, so secrets can be edited and
  # re-keyed from the deploy machine. Private half: ~/.ssh/agenix.
  adminKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJl3RK/gkxLiFzZOAf5Y29hzgWX+vGUE42iPz7RAm9KH agenix-secrets"
  ];

  # ./deploy refuses to run inside these windows unless given --force.
  # day: Mon..Sun, times are 24h local time on the deploy machine; `to` is
  # exclusive. A window can't cross midnight, so split it per day.
  # Saturday noon through Sunday 1pm:
  blackout = [
    { day = "Sat"; from = "12:00"; to = "24:00"; }
    { day = "Sun"; from = "00:00"; to = "13:00"; }
  ];

  # Shared text on every wallpaper's info card (modules/wallpaper.nix).
  # The support number lives in secrets/support.age, not here: edit it with
  # agenix so the real line is never published for spam callers to scrape.
  wallpaper = {
    title = "Mission Church Production";
  };

  # Production network shared by every host with a static `ip`
  # (modules/network.nix). Hosts without `ip` stay on DHCP.
  network = {
    subnetMask = "255.255.252.0"; # 192.168.104.0/22
    router = "192.168.104.1";
    dns = [ "1.1.1.1" "8.8.8.8" ];
  };

  # role:  file in ./roles
  # apps:  extra apps from the catalog in modules/apps.nix (added to the role's)
  # label: computer name (default: name upper-cased, "-" -> " ")
  # location, function: lines on the wallpaper card (function defaults to label)
  # ip:    static address on the production network (see `network` above)
  # config: optional inline nix-darwin module for one-off overrides
  # Machines are reached at `address`, else `ip`, else <name>.local.
  hosts = {
    # Hot spare: carries every CG app so it can stand in for any of them.
    west-cg5hs = {
      role = "cg";
      apps = [ "propresenter" "resolume" ];
      function = "CG 5 - Hot Spare";
      ip = "192.168.105.95";
    };
    west-cg1 = { role = "cg"; apps = [ "propresenter" ]; ip = "192.168.105.91"; };
    west-cg2 = { role = "cg"; apps = [ "propresenter" ]; ip = "192.168.105.92"; };
    west-cg3 = {
      role = "cg";
      apps = [ "resolume" ];
      location = "West Auditorium";
      function = "CG 3 - Resolume";
      ip = "192.168.105.93";
    };
    west-cg4 = { role = "cg"; apps = [ "propresenter" "spotify" "13-years-producer" ]; ip = "192.168.105.94"; };
    audio = { role = "audio"; };
    lighting = { role = "lighting"; };
    service-director = { role = "service-director"; };
    video = { role = "video"; };
  };
}
