# App catalog. Roles and hosts pick apps by name; this file is the only place
# that knows how each one is installed.
#
#   cask:      Homebrew cask that installs it
#   installer: vendor .pkg we pin ourselves (download is behind a vendor
#              login/form, so no cask). Fields:
#                url   where to download it
#                file  exact .pkg file name, kept in ~/ProductionInstallers on
#                      the deploy Mac (null = not pinned yet: warn only)
#                hash  `nix hash file <pkg>`
#                check path that exists once installed (used while unpinned)
#   launch:    app name passed to `open -a` at login
{ config, lib, pkgs, ... }:

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

    desktop-video.installer = {
      url = "https://www.blackmagicdesign.com/support/family/capture-and-playback";
      file = null;
      hash = null;
      check = "/Applications/Blackmagic Desktop Video";
    };

    dante-virtual-soundcard.installer = {
      url = "https://my.audinate.com/";
      file = null;
      hash = null;
      check = "/Applications/Dante Virtual Soundcard.app";
    };
  };

  selected = lib.genAttrs (lib.unique config.production.apps) (name: catalog.${name});
  pick = field: lib.filterAttrs (_: app: app ? ${field}) selected;

  # The .pkg enters the deploy Mac's store via `nix-store --add-fixed` (done by
  # ./deploy) and reaches each machine inside the system closure.
  fetchInstaller = i: pkgs.requireFile {
    name = i.file;
    inherit (i) hash url;
    message = ''
      ${i.file} is not in the Nix store. Download it from
        ${i.url}
      into ~/ProductionInstallers on this Mac, then re-run ./deploy.
    '';
  };

  # Install when the pinned .pkg differs from what this machine last installed.
  installScript = name: i:
    if i.file == null then ''
      if [ ! -e ${lib.escapeShellArg i.check} ]; then
        echo "warning: ${name} is not installed and not pinned in modules/apps.nix. Download it from ${i.url}" >&2
      fi
    '' else
      let pkg = fetchInstaller i; in ''
        if [ "$(cat /var/db/production-installers/${name} 2>/dev/null)" != ${pkg} ]; then
          echo "installing ${i.file}..."
          if installer -pkg ${pkg} -target /; then
            mkdir -p /var/db/production-installers
            echo ${pkg} > /var/db/production-installers/${name}
            echo "note: ${name} changed; restart this Mac and approve any system extension prompt" >&2
          else
            echo "error: installing ${i.file} failed" >&2
          fi
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
      lib.concatStrings (lib.mapAttrsToList (name: app: installScript name app.installer) (pick "installer"));
  };
}
