# Log the operator account in automatically after boot or a power cut, so the
# show apps come back without anyone typing a password.
#
# Requires FileVault to be OFF (macOS ignores auto-login otherwise) and the
# operator password in secrets/autologin-password.age. Without that secret this
# module does nothing.
{ config, lib, pkgs, inventory, ... }:

let
  secretFile = ../secrets/autologin-password.age;

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
in
lib.mkIf (builtins.pathExists secretFile) {
  age.secrets.autologin-password.file = secretFile;

  system.defaults.loginwindow.autoLoginUser = inventory.user;

  system.activationScripts.postActivation.text = ''
    ${writeKcpassword} < ${config.age.secrets.autologin-password.path} > /etc/kcpassword
    chmod 600 /etc/kcpassword
  '';
}
