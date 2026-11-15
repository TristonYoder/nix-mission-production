# Delete what macOS and vendor installers put on a Mac that a show machine
# doesn't need. Runs at the end of every deploy, after apps are installed, so
# anything that comes back (a vendor reinstall, a macOS update) goes again.
#
# Apple's built-in apps (Mail, Messages, Maps, ...) are on the sealed system
# volume and can't be deleted; modules/apps.nix keeps them off the Dock.
{ config, lib, ... }:

{
  options.production.remove = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Paths deleted on every deploy. Lists from modules, roles and hosts are merged.";
  };

  config = {
    # Preinstalled on new Macs, plus leftovers found on the old CGs.
    production.remove = [
      "/Applications/GarageBand.app"
      "/Library/Application Support/GarageBand"
      "/Library/Audio/Apple Loops"
      "/Applications/iMovie.app"
      "/Applications/Keynote Creator Studio.app"
      "/Applications/Numbers Creator Studio.app"
      "/Applications/Pages Creator Studio.app"
      # Keynote stays: ProPresenter's Keynote import needs it.
      "/Applications/Numbers.app"
      "/Applications/Pages.app"

      # Found on the old CGs, not used on a show machine. TeamViewer and
      # Chrome Remote Desktop are not listed: they register launchd services
      # (and TeamViewer a login plugin) that deleting files would leave
      # behind. Remove those with their vendor uninstallers.
      "/Applications/Frame.io Transfer.app"
      "/Applications/13 Years Pager.app"
    ];

    # No desktop widgets, and clicking the wallpaper doesn't sweep every
    # window (and the show output) off screen to reveal them.
    system.defaults.WindowManager = {
      StandardHideWidgets = true;
      StageManagerHideWidgets = true;
      EnableStandardClickToShowDesktop = false;
    };

    system.activationScripts.postActivation.text = lib.mkAfter (lib.concatMapStrings (path: ''
      if [ -e ${lib.escapeShellArg path} ]; then
        echo ${lib.escapeShellArg "removing ${path}"}
        rm -rf ${lib.escapeShellArg path}
      fi
    '') (lib.unique config.production.remove));
  };
}
