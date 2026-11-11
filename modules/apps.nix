# App catalog. Roles and hosts pick apps by name; this file is the only place
# that knows how each one is installed.
#
#   cask:   Homebrew cask that installs it
#   vendor: no cask exists (installer is behind a vendor login/form). Installed
#           by hand; activation warns while `check` path is missing.
#   launch: app name passed to `open -a` at login
{ config, lib, ... }:

let
  catalog = {
    chrome.cask = "google-chrome";
    spotify.cask = "spotify";

    propresenter = {
      cask = "propresenter";
      launch = "ProPresenter";
    };

    resolume = {
      cask = "resolume-arena";
      launch = "Arena";
    };

    dante-controller.cask = "dante-controller";

    desktop-video.vendor = {
      url = "https://www.blackmagicdesign.com/support/family/capture-and-playback";
      check = "/Applications/Blackmagic Desktop Video";
    };

    dante-virtual-soundcard.vendor = {
      url = "https://my.audinate.com/";
      check = "/Applications/Dante Virtual Soundcard.app";
    };
  };

  selected = lib.genAttrs (lib.unique config.production.apps) (name: catalog.${name});
  pick = field: lib.filterAttrs (_: app: app ? ${field}) selected;
  missingCheck = name: app: ''
    if [ ! -e ${lib.escapeShellArg app.vendor.check} ]; then
      echo "warning: ${name} is not installed. Download it from ${app.vendor.url}" >&2
    fi
  '';
in
{
  options.production.apps = lib.mkOption {
    type = lib.types.listOf (lib.types.enum (lib.attrNames catalog));
    default = [ ];
    description = "Apps from the catalog in modules/apps.nix. Lists from roles and hosts are merged.";
  };

  config = {
    homebrew.casks = lib.mapAttrsToList (_: app: app.cask) (pick "cask");

    launchd.user.agents = lib.mapAttrs' (name: app:
      lib.nameValuePair "launch-${name}" {
        serviceConfig = {
          ProgramArguments = [ "/usr/bin/open" "-a" app.launch ];
          RunAtLoad = true;
        };
      }) (pick "launch");

    system.activationScripts.postActivation.text =
      lib.concatStrings (lib.mapAttrsToList missingCheck (pick "vendor"));
  };
}
