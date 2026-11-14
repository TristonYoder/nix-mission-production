# Unattended RustDesk on every Mac: the app, its system service, a permanent
# password, and enrollment in the self-hosted RustDesk console, so support can
# connect without anyone at the machine clicking "accept".
#
# Everything about the server lives in secrets/rustdesk.age, so the address is
# never published in this repo. One KEY=value per line:
#
#   SERVER=<ID/relay server host>
#   KEY=<server public key>
#   API=<console URL>            (optional; default https://<SERVER>)
#   PASSWORD=<permanent password for unattended access>
#   TOKEN=<console API token with device + address book write>
#
# Edit it with:
#   cd secrets && nix develop .. -c agenix -e rustdesk.age -i ~/.ssh/agenix
#
# Each Mac lands in the console's "Mission Production" device group and address
# book, which must already exist there. Without the secret this module does
# nothing.
#
# macOS still wants two clicks per Mac, once: System Settings > Privacy &
# Security > Screen & System Audio Recording and Accessibility, both on for
# RustDesk. Until then sessions connect but show a black screen / no control.
#
# Its menu bar icon is hidden (production.rustdesk.showIcon). RustDesk's own
# hide-tray switch only works in signed custom builds, so this sets the
# per-app visibility macOS keeps for a status item -- the same thing
# ⌘-dragging the icon off the menu bar does.
{ config, lib, pkgs, ... }:

let
  cfg = config.production.rustdesk;
  secretFile = ../secrets/rustdesk.age;
  group = "Mission Production";

  app = "/Applications/RustDesk.app";
  rd = "${app}/Contents/MacOS/RustDesk";

  # The same two units RustDesk's own "Install" button writes
  # (src/platform/privileges_scripts in the RustDesk repo). The app looks for
  # these exact paths to decide it is installed.
  daemonLabel = "com.carriez.RustDesk_service";
  agentLabel = "com.carriez.RustDesk_server";

  # Options and the password go in over IPC to the RustDesk server running in
  # the logged-in session; root may do this from the CLI. A stamp keeps it from
  # re-running (and briefly reconnecting clients) on every deploy.
  provision = pkgs.writeShellApplication {
    name = "rustdesk-provision";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];
    text = ''
      state=/var/db/rustdesk-agent
      mkdir -p "$state"
      chmod 700 "$state"

      if [ ! -x ${lib.escapeShellArg rd} ]; then
        echo "warning: RustDesk is not installed yet; settings apply on the next deploy" >&2
        exit 0
      fi

      # agenix decrypts from a launchd job started earlier in this activation.
      secret=${config.age.secrets.rustdesk.path}
      for _ in $(seq 1 30); do
        [ -s "$secret" ] && break
        sleep 1
      done
      if [ ! -s "$secret" ]; then
        echo "warning: $secret is missing; RustDesk settings apply on the next deploy" >&2
        exit 0
      fi

      SERVER="" KEY="" API="" PASSWORD="" TOKEN=""
      while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
          SERVER=*) SERVER=''${line#SERVER=} ;;
          KEY=*) KEY=''${line#KEY=} ;;
          API=*) API=''${line#API=} ;;
          PASSWORD=*) PASSWORD=''${line#PASSWORD=} ;;
          TOKEN=*) TOKEN=''${line#TOKEN=} ;;
        esac
      done < "$secret"
      [ -n "$API" ] || API="https://$SERVER"
      if [ -z "$SERVER" ] || [ -z "$KEY" ] || [ -z "$PASSWORD" ]; then
        echo "error: secrets/rustdesk.age needs SERVER, KEY and PASSWORD" >&2
        exit 0
      fi

      # The server in the operator's session (auto-login) serves the IPC the
      # CLI talks to. Make sure the units are loaded and give it time to start.
      uid=$(/usr/bin/stat -f %u /dev/console)
      launchctl print system/${daemonLabel} >/dev/null 2>&1 \
        || launchctl bootstrap system /Library/LaunchDaemons/${daemonLabel}.plist 2>/dev/null || true
      if [ "$uid" != 0 ]; then
        launchctl print "gui/$uid/${agentLabel}" >/dev/null 2>&1 \
          || launchctl bootstrap "gui/$uid" /Library/LaunchAgents/${agentLabel}.plist 2>/dev/null || true
      fi
      for _ in $(seq 1 30); do
        [ -S "/tmp/RustDesk-$uid/ipc" ] && break
        sleep 1
      done
      if [ ! -S "/tmp/RustDesk-$uid/ipc" ]; then
        echo "warning: RustDesk is not running in a session yet; settings apply on the next deploy" >&2
        exit 0
      fi

      want=$(printf '%s\n' "$SERVER" "$KEY" "$API" "$PASSWORD" | sha256sum | cut -d' ' -f1)
      if [ "$(cat "$state/applied" 2>/dev/null || true)" != "$want" ]; then
        ${rd} --option custom-rendezvous-server "$SERVER"
        ${rd} --option relay-server "$SERVER"
        ${rd} --option api-server "$API"
        ${rd} --option key "$KEY"
        ${rd} --option verification-method use-permanent-password
        ${rd} --option approve-mode password
        # The CLI only takes the password as an argument.
        out=$(${rd} --password "$PASSWORD" 2>&1 || true)
        case "$out" in
          *Done*)
            printf %s "$want" > "$state/applied"
            echo "RustDesk settings and password applied" ;;
          *)
            echo "warning: setting the RustDesk password failed: $out" >&2
            exit 0 ;;
        esac
      fi

      # The icon's visibility is read when the item is created, so restart the
      # menu bar agent once when it changes (drops any live session).
      tray=${if cfg.showIcon then "shown" else "hidden"}
      if [ "$uid" != 0 ] && [ "$(cat "$state/tray" 2>/dev/null || true)" != "$tray" ]; then
        launchctl kickstart -k "gui/$uid/${agentLabel}" 2>/dev/null || true
        printf %s "$tray" > "$state/tray"
      fi

      [ -n "$TOKEN" ] || exit 0
      id=$(${rd} --get-id 2>/dev/null | tail -n1 || true)
      if [ -z "$id" ]; then
        echo "warning: no RustDesk ID yet; enrollment runs on the next deploy" >&2
        exit 0
      fi
      enrolled="$id $want"
      if [ "$(cat "$state/enrolled" 2>/dev/null || true)" = "$enrolled" ]; then
        exit 0
      fi
      name=$(scutil --get ComputerName)
      # Empty response = success, which the CLI prints as "Done!".
      out=$(${rd} --assign --token "$TOKEN" \
        --device_name "$name" \
        --device_group_name ${lib.escapeShellArg group} \
        --address_book_name ${lib.escapeShellArg group} \
        --address_book_alias "$name" \
        --address_book_password "$PASSWORD" 2>&1 || true)
      case "$out" in
        *Done*)
          printf %s "$enrolled" > "$state/enrolled"
          echo "RustDesk $id enrolled in ${group}" ;;
        *)
          echo "warning: RustDesk enrollment failed: $out" >&2 ;;
      esac
    '';
  };
in
{
  options.production.rustdesk.showIcon = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Show RustDesk's icon in the menu bar.";
  };

  config = lib.mkIf (builtins.pathExists secretFile) {
    age.secrets.rustdesk.file = secretFile;

    # Status items without an autosave name are saved as Item-<n>; RustDesk has one.
    system.defaults.CustomUserPreferences."com.carriez.rustdesk"."NSStatusItem Visible Item-0" = cfg.showIcon;

    production.apps = [ "rustdesk" ];

    launchd.daemons.${daemonLabel}.serviceConfig = {
      Label = daemonLabel;
      ProgramArguments = [ "${app}/Contents/MacOS/service" ];
      WorkingDirectory = "${app}/Contents/MacOS/";
      KeepAlive = true;
      RunAtLoad = true;
      ThrottleInterval = 1;
      StandardOutPath = "/var/log/rustdesk_service.out";
      StandardErrorPath = "/var/log/rustdesk_service.err";
    };

    launchd.agents.${agentLabel}.serviceConfig = {
      Label = agentLabel;
      ProgramArguments = [ rd "--server" ];
      WorkingDirectory = "${app}/Contents/MacOS/";
      LimitLoadToSessionType = [ "LoginWindow" "Aqua" ];
      KeepAlive = { SuccessfulExit = false; AfterInitialDemand = false; };
      RunAtLoad = true;
      ThrottleInterval = 1;
      ProcessType = "Interactive";
    };

    # Never fails the deploy: a show machine that can't reach the console still
    # has to come up. Problems print as warnings.
    system.activationScripts.postActivation.text = ''
      ${lib.getExe provision} || echo "warning: RustDesk provisioning failed" >&2
    '';
  };
}
