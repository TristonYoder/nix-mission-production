# Generic Macs (production.generic, inventory.generic) have no deploy Mac
# pushing to them, so they pull: every 15 minutes, if main on GitHub has moved,
# build that exact commit and switch to it. Outside the blackout windows only.
#
# This is also how a new Mac picks up its secrets: once its enrollment PR
# (host key + re-keyed secrets, see .github/workflows/enroll-host.yml) is
# merged, the next run switches to a build whose secrets it can decrypt, and
# RustDesk, WiFi and the rest configure themselves.
#
# Log: /var/log/follow-main.log. Run it now: sudo launchctl kickstart system/org.missionproduction.follow-main
{ config, lib, pkgs, inventory, ... }:

let
  g = inventory.generic;
  stateDir = "/var/db/org.missionproduction.follow-main";
  firstbootPlist = "/Library/LaunchDaemons/org.missionproduction.firstboot.plist";
  blackout = lib.concatMapStringsSep "\n" (b: "${b.day} ${b.from} ${b.to}") inventory.blackout;

  follow = pkgs.writeShellApplication {
    name = "follow-main";
    runtimeInputs = [ pkgs.git pkgs.jq pkgs.coreutils ];
    text = ''
      log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

      # The first-boot package does the first switch itself; stay out of its way.
      if [ -e ${firstbootPlist} ]; then
        exit 0
      fi

      today=$(date +%a) now=$(date +%H:%M)
      while read -r day from to; do
        [ -n "$day" ] || continue
        if [ "$day" = "$today" ] && [[ ! "$now" < "$from" ]] && [[ "$now" < "$to" ]]; then
          exit 0
        fi
      done <<'EOF'
      ${blackout}
      EOF

      rev=$(git ls-remote https://github.com/${g.repo} refs/heads/main 2>/dev/null | cut -f1 || true)
      if [ -z "$rev" ]; then
        log "GitHub unreachable; trying again later"
        exit 0
      fi
      current=$(jq -r '.configurationRevision // ""' /run/current-system/darwin-version.json 2>/dev/null || true)
      [ "$rev" != "$current" ] || exit 0

      # A commit that fails to build or activate is retried 3 times, then left
      # until main moves again.
      mkdir -p ${stateDir}
      read -r failedRev tries 2>/dev/null < ${stateDir}/failed || true
      if [ "''${failedRev:-}" = "$rev" ] && [ "''${tries:-0}" -ge 3 ]; then
        exit 0
      fi

      log "switching ''${current:-?} -> $rev"
      # Pinned to the commit: no stale cached branch, and every Mac on the same
      # commit runs the same system.
      if /run/current-system/sw/bin/darwin-rebuild switch \
           --flake "github:${g.repo}/$rev#${g.prefix}"; then
        rm -f ${stateDir}/failed
        log "now on $rev"
      else
        [ "''${failedRev:-}" = "$rev" ] || tries=0
        echo "$rev $(( ''${tries:-0} + 1 ))" > ${stateDir}/failed
        log "switch to $rev failed"
        exit 1
      fi
    '';
  };
in
lib.mkIf config.production.generic {
  launchd.daemons.follow-main.serviceConfig = {
    Label = "org.missionproduction.follow-main";
    ProgramArguments = [ (lib.getExe follow) ];
    RunAtLoad = true;
    StartInterval = 900;
    # Activation reloads this job when its script changes, which would stop the
    # switch that is doing it halfway. Let darwin-rebuild finish on its own.
    AbandonProcessGroup = true;
    StandardOutPath = "/var/log/follow-main.log";
    StandardErrorPath = "/var/log/follow-main.log";
  };
}
