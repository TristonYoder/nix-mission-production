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
#                marker  optional file that puts the vendor's installer in silent
#                        mode, created only while it runs
#   launch:    app name passed to `open -a` at login
#   dock:      app bundle shown in the Dock (apps without one stay off it)
#   remove:    paths the vendor installs that we don't want (see
#              modules/cleanup.nix)
{ config, lib, pkgs, ... }:

let
  catalog = {
    chrome = {
      cask = "google-chrome";
      dock = "/Applications/Google Chrome.app";
    };

    spotify = {
      cask = "spotify";
      dock = "/Applications/Spotify.app";
    };

    propresenter = {
      cask = "propresenter";
      launch = "ProPresenter";
      dock = "/Applications/ProPresenter.app";
    };

    resolume = {
      cask = "resolume-arena";
      launch = "Arena";
      dock = "/Applications/Resolume Arena/Arena.app";
    };

    dante-controller = {
      cask = "dante-controller";
      dock = "/Applications/Dante Controller.app";
    };

    swiftbar = {
      cask = "swiftbar";
      launch = "SwiftBar";
    };

    # Remote support. Its launchd service and settings: modules/rustdesk.nix.
    rustdesk = {
      cask = "rustdesk";
    };

    desktop-video = {
      dock = "/Applications/Blackmagic Desktop Video/Desktop Video Setup.app";
      # Its updater prompts operators to update drivers; versions change only
      # through the pin below.
      remove = [ "/Library/LaunchAgents/com.blackmagic-design.DesktopVideoUpdater.plist" ];
      installer = {
        url = "https://www.blackmagicdesign.com/support/family/capture-and-playback";
        # "Install Desktop Video 16.5.pkg" from the 16.5 .dmg, renamed (Nix store
        # names can't contain spaces).
        file = "Desktop_Video_16.5.pkg";
        hash = "sha256-LBhZvK3WjZS55isFnWSfl/OQSeXUsawrcPMk0gvq64Y=";
        check = "/Applications/Blackmagic Desktop Video";
      };
    };

    # Driver for the Sonnet Twin10G 10GBASE-T PCIe card (G10E-2X-E3, Intel X540),
    # the CG machines' add-in NIC. Sonnet lists Mac Pro 14,8 (Apple Silicon) and
    # Thunderbolt expansion systems on macOS 15+. Support library:
    # https://support.sonnettech.com/support/kb/kb.php?cat=513
    sonnet-twin10g = {
      installer = {
        url = "https://support.sonnettech.com/download.php?f=software/SonnetEthernet-10GE-1.8.4.dmg";
        # Not pinned yet: copy the .pkg out of SonnetEthernet-10GE-1.8.4.dmg into
        # ~/ProductionInstallers, then set file and hash. check is a guess at
        # the install path; correct it from the .pkg's contents when pinning.
        file = null;
        hash = null;
        check = "/Library/DriverExtensions/SonnetEthernet10GE.dext";
      };
    };

    dante-virtual-soundcard = {
      dock = "/Applications/Dante Virtual Soundcard.app";
      installer = {
        url = "https://my.audinate.com/";
        # DanteVirtualSoundcard.pkg from DVS-4.5.2.3_macos.dmg, renamed.
        file = "DanteVirtualSoundcard_4.5.2.3.pkg";
        hash = "sha256-ZPehzUX0TfvNgSz8+So3BKXNBRLPoa4NDJrySoBHH48=";
        check = "/Applications/Dante Virtual Soundcard.app";
        # From the .dmg's own .scripts/dvs_silent_install.sh.
        marker = "/tmp/DVS_silent_install";
      };
    };
  };

  names = lib.unique config.production.apps;
  selected = lib.genAttrs names (name: catalog.${name});
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
      let
        pkg = fetchInstaller i;
        marker = i.marker or null;
      in ''
        if [ "$(cat /var/db/production-installers/${name} 2>/dev/null)" != ${pkg} ]; then
          echo "installing ${i.file}..."
          ${lib.optionalString (marker != null) "touch ${lib.escapeShellArg marker}"}
          if installer -pkg ${pkg} -target /; then
            mkdir -p /var/db/production-installers
            echo ${pkg} > /var/db/production-installers/${name}
            echo "note: ${name} changed; restart this Mac and approve any system extension prompt" >&2
          else
            echo "error: installing ${i.file} failed" >&2
          fi
          ${lib.optionalString (marker != null) "rm -f ${lib.escapeShellArg marker}"}
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

    # Only this machine's apps, in the order they're listed. Apple's own apps
    # can't be deleted, so keeping them off the Dock is the cleanup for those.
    system.defaults.dock.persistent-apps =
      lib.concatMap (name: lib.optional (catalog.${name} ? dock) catalog.${name}.dock) names
      ++ [ "/System/Applications/System Settings.app" ];

    production.remove = lib.concatLists (lib.mapAttrsToList (_: app: app.remove) (pick "remove"));

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
