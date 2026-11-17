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
#   dmg:       signed .app we pin from a public .dmg (no cask). Fields:
#                url   download URL
#                hash  `nix hash file <dmg>` (or from the release's SHA256SUMS)
#                app   bundle name inside the .dmg, copied to /Applications
#   app:       bundle a cask installs as a plain .app (not a .pkg). Homebrew
#              won't install over a copy it didn't put there, so
#              `./deploy bootstrap` moves such hand-installed copies aside.
#   launch:    app name passed to `open -a` at login
#   ready:     shell test that passes once the app's service is up
#   after:     apps whose `ready` must pass before this one launches at login
#              (only those this machine has; gives up after 10 seconds and
#              launches anyway)
#   dock:      app bundle shown in the Dock (apps without one stay off it, and
#              so does this one until it's actually installed)
#   remove:    paths the vendor installs that we don't want (see
#              modules/cleanup.nix)
{ config, lib, pkgs, ... }:

let
  catalog = {
    chrome = {
      cask = "google-chrome";
      app = "/Applications/Google Chrome.app";
      dock = "/Applications/Google Chrome.app";
    };

    # Signs in per machine; set it to stream (not mirror) so it doesn't fill the disk.
    google-drive = {
      cask = "google-drive";
    };

    spotify = {
      cask = "spotify";
      app = "/Applications/Spotify.app";
      dock = "/Applications/Spotify.app";
    };

    propresenter = {
      cask = "propresenter";
      app = "/Applications/ProPresenter.app";
      launch = "ProPresenter";
      # Opened before Dante is up, it falls back to the built-in audio device
      # (same for Resolume below).
      after = [ "dante-virtual-soundcard" ];
      dock = "/Applications/ProPresenter.app";
    };

    resolume = {
      cask = "resolume-arena";
      launch = "Arena";
      after = [ "dante-virtual-soundcard" ];
      dock = "/Applications/Resolume Arena/Arena.app";
    };

    dante-controller = {
      cask = "dante-controller";
      dock = "/Applications/Dante Controller.app";
    };

    swiftbar = {
      cask = "swiftbar";
      app = "/Applications/SwiftBar.app";
      launch = "SwiftBar";
    };

    # Remote support. Its launchd service and settings: modules/rustdesk.nix.
    rustdesk = {
      cask = "rustdesk";
      app = "/Applications/RustDesk.app";
    };

    desktop-video = {
      dock = "/Applications/Blackmagic Desktop Video/Desktop Video Setup.app";
      # Its updater agent prompts operators at login to flash card firmware;
      # versions change only through the pin below, and the deploy flashes
      # firmware to match (roles/cg.nix).
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

    atem-software-control = {
      dock = "/Applications/Blackmagic ATEM Switchers/ATEM Software Control.app";
      installer = {
        url = "https://www.blackmagicdesign.com/support/family/atem-live-production-switchers";
        file = null; # not pinned yet: download the ATEM Switchers .pkg and pin it here
        hash = null;
        check = "/Applications/Blackmagic ATEM Switchers/ATEM Software Control.app";
      };
    };

    # 13 Years: Developer ID signed and notarized builds from GitHub Releases.
    # Bump both together: same release, same version.
    "13-years-producer" = {
      launch = "13 Years Producer";
      dock = "/Applications/13 Years Producer.app";
      dmg = {
        url = "https://github.com/TristonYoder/13years/releases/download/v1.8.0/13-Years-Producer-1.8.0.dmg";
        hash = "sha256-PuSZ6N6bs3plzpfhjtaQvNGReXT+kfCvKZSYR8ij5FA=";
        app = "13 Years Producer.app";
      };
    };

    # The pager. Its settings: modules/pager.nix. Off the Dock: it lives in the
    # menu bar.
    "13-years-pager" = {
      launch = "13 Years";
      dmg = {
        url = "https://github.com/TristonYoder/13years/releases/download/v1.8.0/13-Years-1.8.0.dmg";
        hash = "sha256-wxtaCIdNehqrXLHvQ/oQekv+sprJzV00REKRj96w5J0=";
        app = "13 Years.app";
      };
    };

    dante-virtual-soundcard = {
      dock = "/Applications/Dante Virtual Soundcard.app";
      # Its CoreAudio device exists (the daemon has started it).
      ready = "/usr/sbin/system_profiler SPAudioDataType 2>/dev/null | /usr/bin/grep -q 'Dante Virtual Soundcard'";
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

  dockApps =
    lib.concatMap (name: lib.optional (catalog.${name} ? dock) catalog.${name}.dock) names
    ++ [ "/System/Applications/System Settings.app" ];

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
  # Wait for the `after` apps this machine has, then open the app.
  launchScript = name: app:
    let
      deps = lib.filter (dep: selected ? ${dep} && selected.${dep} ? ready) (app.after or [ ]);
      ready = lib.concatMapStringsSep " && " (dep: "(${selected.${dep}.ready})") deps;
    in
    lib.optionalString (deps != [ ]) ''
      deadline=$(( $(/bin/date +%s) + 10 ))
      until ${ready}; do
        if [ "$(/bin/date +%s)" -ge "$deadline" ]; then
          /usr/bin/logger -t launch-${name} "${lib.concatStringsSep ", " deps} not ready after 10 seconds; launching anyway"
          break
        fi
        sleep 1
      done
    '' + "exec /usr/bin/open -a ${lib.escapeShellArg app.launch}";

  # Copy the .app out of the pinned .dmg when it differs from what this machine
  # last installed. A running copy is quit first and reopened after, so the new
  # version is what runs.
  dmgScript = name: d:
    let
      dmg = pkgs.fetchurl { inherit (d) url hash; };
      app = "/Applications/${d.app}";
      process = lib.removeSuffix ".app" d.app;
    in ''
      if [ "$(cat /var/db/production-installers/${name} 2>/dev/null)" != ${dmg} ] || [ ! -d ${lib.escapeShellArg app} ]; then
        echo "installing ${d.app}..."
        mnt=$(mktemp -d)
        if hdiutil attach -nobrowse -readonly -noverify -mountpoint "$mnt" ${dmg} >/dev/null; then
          running=0
          if pgrep -xq ${lib.escapeShellArg process}; then
            running=1
            pkill -x ${lib.escapeShellArg process} || true
            for _ in $(seq 1 20); do pgrep -xq ${lib.escapeShellArg process} || break; sleep 0.5; done
          fi
          rm -rf ${lib.escapeShellArg app}
          if ditto "$mnt/"${lib.escapeShellArg d.app} ${lib.escapeShellArg app}; then
            mkdir -p /var/db/production-installers
            echo ${dmg} > /var/db/production-installers/${name}
          else
            echo "error: copying ${d.app} failed" >&2
          fi
          hdiutil detach "$mnt" -quiet || true
          if [ "$running" = 1 ]; then
            uid=$(id -u ${lib.escapeShellArg config.system.primaryUser})
            launchctl asuser "$uid" sudo -u ${lib.escapeShellArg config.system.primaryUser} open -a ${lib.escapeShellArg app} || true
          fi
        else
          echo "error: mounting ${dmg} failed" >&2
        fi
        rmdir "$mnt" 2>/dev/null || true
      fi
    '';
in
{
  options.production = {
    apps = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames catalog));
      default = [ ];
      description = "Apps from the catalog in modules/apps.nix. Lists from roles and hosts are merged.";
    };

    caskApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      readOnly = true;
      default = lib.mapAttrsToList (_: app: "${app.cask}|${app.app}") (pick "app");
      description = "cask|bundle for this host's .app casks; read by ./deploy bootstrap.";
    };
  };

  config = {
    homebrew.casks = lib.mapAttrsToList (_: app: app.cask) (pick "cask");

    # Only this machine's apps, in the order they're listed, and only those
    # actually on disk: a missing bundle shows as a "?" in the Dock. Written
    # last in activation (after casks and installers), not via
    # system.defaults.dock.persistent-apps, which nix-darwin writes before
    # anything is installed. Apple's own apps can't be deleted, so keeping them
    # off the Dock is the cleanup for those.
    system.activationScripts.postActivation.text = lib.mkMerge [
      (lib.concatStrings (lib.mapAttrsToList (name: app: installScript name app.installer) (pick "installer")))
      (lib.concatStrings (lib.mapAttrsToList (name: app: dmgScript name app.dmg) (pick "dmg")))

      (lib.mkAfter (let
        user = lib.escapeShellArg config.system.primaryUser;
        tile = path: lib.escapeShellArg (
          "<dict><key>tile-data</key><dict><key>file-data</key><dict>"
          + "<key>_CFURLString</key><string>${lib.escapeXML path}</string>"
          + "<key>_CFURLStringType</key><integer>0</integer>"
          + "</dict></dict></dict>");
        addTile = path: ''
          if [ -e ${lib.escapeShellArg path} ]; then
            dockTiles="$dockTiles"${tile path}
          else
            echo "note: ${path} is not installed; leaving it off the Dock" >&2
          fi
        '';
      in ''
        echo >&2 "setting the Dock..."
        dockTiles=
        ${lib.concatMapStrings addTile dockApps}
        launchctl asuser "$(id -u -- ${user})" sudo --user=${user} -- defaults write com.apple.dock persistent-apps \
          '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><array>'"$dockTiles"'</array></plist>'
        killall -qu ${user} Dock || true
      ''))
    ];

    production.remove = lib.concatLists (lib.mapAttrsToList (_: app: app.remove) (pick "remove"));

    launchd.user.agents = lib.mapAttrs' (name: app:
      lib.nameValuePair "launch-${name}" {
        serviceConfig = {
          ProgramArguments = [ "/bin/sh" "-c" (launchScript name app) ];
          RunAtLoad = true;
        };
      }) (pick "launch");
  };
}
