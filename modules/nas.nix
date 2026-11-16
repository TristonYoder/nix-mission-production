# The Synology NAS (Mission-NAS, RS3618xs) mounted for the operator, the same
# way Finder's "Connect to Server" does, so media paths match:
#   /Volumes/<share>
#
# The NAS account's password comes from secrets/nas-password.age (the password
# alone, one line). Create or change it with:
#   cd secrets && read -rs "pw?NAS password: " && printf %s "$pw" \
#     | nix develop .. -c agenix -e nas-password.age -i ~/.ssh/agenix; unset pw
#
# A login agent checks every 30 seconds and remounts after a reboot, a network
# drop or a NAS restart. If the NAS is unreachable it waits quietly. Without
# the secret this module does nothing.
{ config, lib, pkgs, inventory, ... }:

let
  cfg = config.production.nas;
  secretFile = ../secrets/nas-password.age;

  mount = pkgs.writeShellApplication {
    name = "production-nas-mount";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      server=${lib.escapeShellArg cfg.server}
      share=${lib.escapeShellArg cfg.share}
      user=${lib.escapeShellArg cfg.user}
      secret=${config.age.secrets.nas-password.path}

      # Already mounted (by this agent or by hand in Finder).
      if /sbin/mount | grep -qF " on /Volumes/$share (smbfs"; then
        exit 0
      fi
      [ -r "$secret" ] || exit 0
      /usr/bin/nc -z -G 3 "$server" 445 2>/dev/null || exit 0

      # URL-encode, so any character in the password is safe in smb://.
      pass=$(jq -rn --rawfile p "$secret" '$p | rtrimstr("\n") | @uri')
      shareEnc=$(jq -rn --arg s "$share" '$s | @uri')
      userEnc=$(jq -rn --arg u "$user" '$u | @uri')

      # Script on stdin, so the password never shows up in `ps`.
      /usr/bin/osascript >/dev/null <<EOF || echo "warning: mounting smb://$user@$server/$share failed" >&2
      mount volume "smb://$userEnc:$pass@$server/$shareEnc"
      EOF
    '';
  };
in
{
  options.production.nas = {
    enable = lib.mkEnableOption "the NAS share mounted at login";
    server = lib.mkOption {
      type = lib.types.str;
      # The NAS's static address. It also answers on 192.168.50.51 (DHCP).
      default = "192.168.50.25";
      description = "NAS host name or IP.";
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

  config = lib.mkIf (cfg.enable && builtins.pathExists secretFile) {
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
      };
    };
  };
}
