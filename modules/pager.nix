# The 13 Years pager on every Mac: cue lights, the countdown and producer
# messages in the menu bar. The app itself comes from the catalog
# ("13-years-pager" in modules/apps.nix); this file sets its preferences.
#
# Any setting left null is left alone, so it can still be changed on the Mac.
# Set ones are rewritten on every deploy that changes them, and the pager is
# restarted so it picks them up.
#
# Roles set `production.pager.role` to the producer role's name, for example
# `production.pager.role = "Audio";` in roles/audio.nix.
{ config, lib, pkgs, inventory, ... }:

let
  cfg = config.production.pager;
  user = config.system.primaryUser;
  domain = "app.13years.pager";
  container = "/Users/${user}/Library/Containers/${domain}/Data/Library/Preferences";
  app = "/Applications/13 Years.app";

  # Preference keys, from the 13 Years source.
  settings = lib.filterAttrs (_: v: v != null) {
    lanUnicastManualProducerHost =
      if cfg.host == null then null
      else if cfg.port == null then cfg.host
      else "${cfg.host}:${toString cfg.port}";
    pagerRoleName = cfg.role;
    pagerLayout = cfg.layout;
    pagerCueDisplay = cfg.cueDisplay;
    keepOnTop = cfg.keepOnTop;
    menuBarShowItem = cfg.menuBar.enable;
    menuBarShowItemName = cfg.menuBar.showItemName;
    menuBarShowUnreadBadge = cfg.menuBar.showUnreadBadge;
    menuBarPriorityTakeover = cfg.menuBar.priorityTakeover;
    menuBarHideDockIcon = cfg.menuBar.hideDockIcon;
  };

  write = key: value:
    "defaults write ${domain} ${key} "
    + (if lib.isBool value then "-bool ${lib.boolToString value}" else "-string ${lib.escapeShellArg value}");

  # Runs as the operator. The pager is sandboxed, so its preferences live in its
  # container, which only exists once it has been opened; macOS sends
  # `defaults write` there from then on.
  apply = pkgs.writeShellScript "pager-preferences" ''
    set -eu
    if [ ! -e ${lib.escapeShellArg container} ]; then
      open -gj -a ${lib.escapeShellArg app}
      for _ in $(seq 1 30); do
        [ -e ${lib.escapeShellArg container} ] && break
        sleep 1
      done
      [ -e ${lib.escapeShellArg container} ] || { echo "warning: 13 Years did not start; pager settings apply on the next deploy" >&2; exit 1; }
    fi
    running=0
    if pgrep -xq "13 Years"; then
      running=1
      osascript -e 'quit app "13 Years"' >/dev/null 2>&1 || pkill -x "13 Years" || true
      for _ in $(seq 1 20); do pgrep -xq "13 Years" || break; sleep 0.5; done
    fi
    ${lib.concatStringsSep "\n    " (lib.mapAttrsToList write settings)}
    [ "$running" = 1 ] && open -a ${lib.escapeShellArg app}
    exit 0
  '';

  stamp = builtins.hashString "sha256" (builtins.toJSON settings);

  nullOr = type: description: lib.mkOption {
    type = lib.types.nullOr type;
    default = null;
    inherit description;
  };
in
{
  options.production.pager = {
    host = nullOr lib.types.str "Producer host or IP. Null: find it automatically on the network.";
    port = nullOr lib.types.port "Producer port, when it isn't the default 13380.";
    role = nullOr lib.types.str "Name of the producer role this Mac shows.";
    layout = nullOr (lib.types.enum [ "automatic" "landscape" "portrait" "lowerThird" ]) "Pager window layout.";
    cueDisplay = nullOr (lib.types.enum [ "outline" "fullscreen" ]) "Cue colour as a frame around the window, or filling it.";
    keepOnTop = nullOr lib.types.bool "Keep the pager window above other windows.";
    menuBar = {
      enable = nullOr lib.types.bool "Show the pager in the menu bar.";
      showItemName = nullOr lib.types.bool "Show the current item's name in the menu bar.";
      showUnreadBadge = nullOr lib.types.bool "Show the unread message count in the menu bar.";
      priorityTakeover = nullOr lib.types.bool "Let an unread high-priority message replace the menu bar countdown.";
      hideDockIcon = nullOr lib.types.bool "Run from the menu bar only, with no Dock icon.";
    };
  };

  config = {
    production.apps = [ "13-years-pager" ];

    # The producer runs on west-cg4.
    production.pager.host = lib.mkDefault inventory.hosts.west-cg4.ip;

    # After modules/apps.nix has installed or updated the app. Re-applied when
    # the settings change, and whenever the app was just reinstalled.
    system.activationScripts.postActivation.text = lib.mkIf (settings != { }) (lib.mkAfter ''
      if [ -d ${lib.escapeShellArg app} ] \
        && { [ "$(cat /var/db/production-installers/pager-preferences 2>/dev/null)" != ${stamp} ] \
          || [ /var/db/production-installers/13-years-pager -nt /var/db/production-installers/pager-preferences ]; }; then
        uid=$(id -u ${lib.escapeShellArg user})
        if [ "$(/usr/bin/stat -f %u /dev/console)" = "$uid" ]; then
          echo "applying 13 Years pager settings..."
          if launchctl asuser "$uid" sudo -u ${lib.escapeShellArg user} ${apply}; then
            echo ${stamp} > /var/db/production-installers/pager-preferences
          fi
        else
          echo "note: ${user} isn't logged in; 13 Years pager settings apply on the next deploy" >&2
        fi
      fi
    '');
  };
}
