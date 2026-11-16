# The operator account's password, and auto-login with it after boot or a power
# cut, so the show apps come back without anyone typing a password.
#
# Both come from secrets/autologin-password.age: the account's password is set
# from it (only when it differs), and /etc/kcpassword is written from it, so the
# two can never drift apart. To change the shared password, edit the secret and
# deploy.
#
# Requires FileVault to be OFF (macOS ignores auto-login otherwise). Without the
# secret this module does nothing.
{ config, lib, pkgs, inventory, ... }:

let
  secretFile = ../secrets/autologin-password.age;
  user = inventory.user;

  # /etc/kcpassword is the password plus a NUL terminator, zero-padded to a
  # multiple of 12 bytes, XORed with a fixed 11-byte key. Same format System
  # Settings writes.
  writeKcpassword = pkgs.writers.writePerl "write-kcpassword" { } ''
    my @key = (0x7D, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD, 0xEA, 0xA3, 0xB9, 0x1F);
    local $/;
    my $pw = <STDIN>;
    $pw =~ s/\n\z//;
    my @bytes = (unpack("C*", $pw), 0);
    push @bytes, 0 while @bytes % 12;
    print pack("C*", map { $bytes[$_] ^ $key[$_ % @key] } 0 .. $#bytes);
  '';

  apply = pkgs.writeShellApplication {
    name = "operator-password";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      secret=${config.age.secrets.autologin-password.path}
      # agenix decrypts from a launchd job started earlier in this activation.
      for _ in $(seq 1 30); do
        [ -s "$secret" ] && break
        sleep 1
      done
      if [ ! -s "$secret" ]; then
        echo "warning: $secret is missing; operator password and auto-login apply on the next deploy" >&2
        exit 0
      fi
      pw=$(cat "$secret")

      if ! /usr/bin/dscl /Local/Default -authonly ${user} "$pw" >/dev/null 2>&1; then
        # Resetting a secure-token holder's password as root would leave its
        # token and login keychain on the old one.
        if /usr/sbin/sysadminctl -secureTokenStatus ${user} 2>&1 | grep -q ENABLED; then
          echo "warning: ${user}'s password differs from the secret, but it holds a secure token; change it in System Settings" >&2
        else
          echo "setting ${user}'s password from secrets/autologin-password.age"
          /usr/bin/dscl . -passwd /Users/${user} "$pw"
        fi
      fi

      ${writeKcpassword} < "$secret" > /etc/kcpassword
      chmod 600 /etc/kcpassword
    '';
  };
in
lib.mkIf (builtins.pathExists secretFile) {
  age.secrets.autologin-password.file = secretFile;

  system.defaults.loginwindow.autoLoginUser = user;

  system.activationScripts.postActivation.text = ''
    ${lib.getExe apply}
  '';
}
