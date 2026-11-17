# The Synology NAS (Mission-NAS, RS3618xs) mounted for the operator, the same
# way Finder's "Connect to Server" does, so media paths match:
#   /Volumes/<share>
#
# The NAS gets a name in /etc/hosts ("Mission-NAS" by default) so it reads as
# smb://Mission-NAS in Finder instead of a bare IP.
#
# The NAS account's password comes from secrets/nas-password.age (the password
# alone, one line). Create or change it with:
#   cd secrets && read -rs "pw?NAS password: " && printf %s "$pw" \
#     | nix develop .. -c agenix -e nas-password.age -i ~/.ssh/agenix; unset pw
#
# A login agent checks every 30 seconds and remounts after a reboot, a network
# drop or a NAS restart. If the NAS is unreachable it waits quietly. It never
# shows a sign-in window: a rejected password is logged to
# ~/Library/Logs/production-nas.log, and the agent stops
# trying (so the NAS doesn't auto-block the Mac) until the secret changes or
# an hour passes. Without the secret it only adds the hosts entry.
{ config, lib, pkgs, inventory, ... }:

let
  cfg = config.production.nas;
  secretFile = ../secrets/nas-password.age;
  hasSecret = builtins.pathExists secretFile;

  begin = "# BEGIN production.nas";
  end = "# END production.nas";

  # NetFS directly, with its no-UI option: unlike `mount volume`, a failure
  # returns an error code instead of opening a sign-in window. The password is
  # read from the secret file here, so it never appears in argv.
  # Credentials go in the URL (percent-encoded): from JXA, NetFS's separate
  # user/password arguments arrive empty and every login fails with EAUTH.
  mountJs = pkgs.writeText "nas-mount.js" ''
    ObjC.import("Foundation");
    ObjC.import("NetFS");
    function run(argv) {
      const [server, share, user, secret] = argv;
      const pass = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(
        secret, $.NSUTF8StringEncoding, null)).replace(/\r?\n$/, "");
      const url = $.NSURL.URLWithString("smb://" + encodeURIComponent(user) +
        ":" + encodeURIComponent(pass) + "@" + server + "/" +
        encodeURIComponent(share));
      const open = $.NSMutableDictionary.dictionary;
      open.setObjectForKey($.kNAUIOptionNoUI, $.kNAUIOptionKey);
      return String($.NetFSMountURLSync(url, null, null, null, open, null, null));
    }
  '';

  mount = pkgs.writeShellApplication {
    name = "production-nas-mount";
    text = ''
      server=${lib.escapeShellArg cfg.name}
      share=${lib.escapeShellArg cfg.share}
      user=${lib.escapeShellArg cfg.user}
      secret=${config.age.secrets.nas-password.path}
      state="$HOME/Library/Caches/production-nas"
      authFailed="$state/auth-failed"

      # Already mounted (by this agent or by hand in Finder).
      if /sbin/mount | grep -qF " on /Volumes/$share (smbfs"; then
        rm -f "$authFailed"
        exit 0
      fi
      [ -r "$secret" ] || exit 0
      /usr/bin/nc -z -G 3 "$server" 445 2>/dev/null || exit 0

      # The NAS rejected this exact password recently: don't hammer it.
      sum=$(/usr/bin/shasum -a 256 "$secret" | cut -d' ' -f1)
      if [ -f "$authFailed" ] && [ "$(cat "$authFailed")" = "$sum" ] \
         && [ -z "$(find "$authFailed" -mmin +60)" ]; then
        exit 0
      fi

      rc=$(/usr/bin/osascript -l JavaScript ${mountJs} \
             "$server" "$share" "$user" "$secret" 2>&1) || true
      case "$rc" in
        0|17) rm -f "$authFailed" ;; # mounted / already mounted
        80)
          echo "error: $server rejected the login for $user; not retrying until secrets/nas-password.age changes (or in an hour)" >&2
          mkdir -p "$state"
          printf %s "$sum" > "$authFailed"
          ;;
        *) echo "warning: mounting smb://$user@$server/$share failed: $rc" >&2 ;;
      esac
    '';
  };
in
{
  options.production.nas = {
    enable = lib.mkEnableOption "the NAS share mounted at login";
    name = lib.mkOption {
      type = lib.types.str;
      default = "Mission-NAS";
      description = "Name the NAS is given in /etc/hosts and mounted by.";
    };
    address = lib.mkOption {
      type = lib.types.str;
      # The NAS's static address. It also answers on 192.168.50.51 (DHCP).
      default = "192.168.50.25";
      description = "NAS IP address that `name` points at.";
    };
    share = lib.mkOption {
      type = lib.types.str;
      default = "Creative Team";
      description = "SMB share to mount at /Volumes/<share>.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = inventory.user;
      description = "Account on the NAS.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # nix-darwin leaves /etc/hosts alone, so keep our own marked block in it.
      system.activationScripts.postActivation.text = ''
        hosts_new=$(mktemp)
        sed '/^${begin}$/,/^${end}$/d' /etc/hosts > "$hosts_new"
        printf '%s\n%s\t%s\n%s\n' ${lib.escapeShellArg begin} \
          ${lib.escapeShellArg cfg.address} ${lib.escapeShellArg cfg.name} \
          ${lib.escapeShellArg end} >> "$hosts_new"
        if ! cmp -s "$hosts_new" /etc/hosts; then
          cat "$hosts_new" > /etc/hosts
          dscacheutil -flushcache
          killall -HUP mDNSResponder 2>/dev/null || true
        fi
        rm -f "$hosts_new"
      '';
    }

    (lib.mkIf hasSecret {
      age.secrets.nas-password = {
        file = secretFile;
        # The mount runs in the operator's session.
        owner = inventory.user;
        mode = "0400";
      };

      launchd.user.agents.nas-mount = {
        command = lib.getExe mount;
        serviceConfig = {
          RunAtLoad = true;
          StartInterval = 30;
          LimitLoadToSessionType = [ "Aqua" ];
          StandardErrorPath = "/Users/${inventory.user}/Library/Logs/production-nas.log";
        };
      };
    })
  ]);
}
