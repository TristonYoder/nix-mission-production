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
  # day: Mon..Sun, times are 24h local time on the deploy machine.
  blackout = [
    { day = "Sun"; from = "06:00"; to = "13:00"; }
  ];

  # Shared text on every wallpaper's info card (modules/wallpaper.nix).
  # The support number lives in secrets/support.age, not here: edit it with
  # agenix so the real line is never published for spam callers to scrape.
  wallpaper = {
    title = "Mission Church Production";
  };

  # role:  file in ./roles
  # apps:  extra apps from the catalog in modules/apps.nix (added to the role's)
  # label: computer name (default: name upper-cased, "-" -> " ")
  # location, function: lines on the wallpaper card (function defaults to label)
  # config: optional inline nix-darwin module for one-off overrides
  # Machines are reached at <name>.local unless `address` is set.
  hosts = {
    cg-1 = { role = "cg"; apps = [ "propresenter" ]; };
    cg-2 = { role = "cg"; apps = [ "propresenter" ]; };
    cg-3 = {
      role = "cg";
      apps = [ "resolume" ];
      location = "West Auditorium";
      function = "CG 3 - Resolume";
    };
    cg-4 = { role = "cg"; apps = [ "propresenter" "spotify" ]; };
    audio = { role = "audio"; };
    lighting = { role = "lighting"; };
    director = { role = "director"; };
  };
}
