# The machine's name in the menu bar (via SwiftBar), with the wallpaper card's
# details in its dropdown, for when windows cover the desktop.
#
# SwiftBar shows plugins left of the system icons; ⌘-drag it next to the clock
# once per Mac and macOS remembers the spot.
{ config, lib, pkgs, ... }:

let
  card = config.production.wallpaper;
  rev = config.system.configurationRevision;

  plugin = pkgs.writeShellApplication {
    name = "machine.sh"; # SwiftBar: no interval in the name, runs on open
    text = ''
      LABEL=${lib.escapeShellArg config.production.label}
      TITLE=${lib.escapeShellArg card.title}
      LOCATION=${lib.escapeShellArg (toString card.location)}
      FUNCTION=${lib.escapeShellArg card.function}
      SUPPORT_FILE=${lib.escapeShellArg config.age.secrets.support.path}
      REVISION=${lib.escapeShellArg (if rev == null then "" else lib.substring 0 7 rev)}
    '' + builtins.readFile ./machine-info.sh + builtins.readFile ./menubar-plugin.sh;
  };
in
{
  production.apps = [ "swiftbar" ];

  # Stable path, so SwiftBar's preference never changes between deploys.
  environment.etc."production-menubar".source = "${plugin}/bin";

  system.defaults.CustomUserPreferences."com.ameba.SwiftBar" = {
    PluginDirectory = "/etc/production-menubar"; # skips the first-run folder prompt
    MakePluginExecutable = false; # plugin lives in the read-only Nix store
    CollectCrashReports = false;
    # Sparkle: never check for or install updates on a show machine.
    SUEnableAutomaticChecks = false;
    SUAutomaticallyUpdate = false;
  };
}
