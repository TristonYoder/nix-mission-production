# Syncthing on every Mac, running as the operator from login. Every Mac with
# Resolume keeps its Resolume folder in sync with the others, apart from the
# per-machine parts in `ignores`.
#
# On those Macs the folder lives at ~/Resolume Arena, and ~/Documents/Resolume
# Arena (where Resolume looks) is a symlink to it: macOS asks before a
# background process like Syncthing reads ~/Documents, and blocks it until
# someone clicks Allow at the Mac -- again after any update. Activation moves
# an existing folder out of Documents once.
#
# Each Mac's identity lives in secrets/syncthing (written by
# `./deploy bootstrap`): <host>.id and <host>.cert.pem are public, the key is
# agenix-encrypted. A Mac without one yet runs Syncthing with a throwaway
# identity and syncs nothing.
#
# Web UI: https://<mac>:8384 from anywhere on the network, user
# `missionproduction` (the operator, system.primaryUser), with
# the password in secrets/syncthing-gui.age (shared by every Mac). Read it with:
#   cd secrets && nix develop .. -c agenix -d syncthing-gui.age -i ~/.ssh/agenix
# The settings below are reapplied at login and on every deploy that changes
# them; anything else can still be changed in the web UI.
#
# From nixpkgs rather than the Homebrew cask: the Nix build has Syncthing's
# self-upgrade compiled out, so it only changes when a deploy changes it.
{ config, lib, pkgs, inventory, ... }:

let
  user = config.system.primaryUser;
  host = config.production.hostName;
  dir = ../secrets/syncthing;
  home = "/Users/${user}/Library/Application Support/Syncthing";
  guiSecret = ../secrets/syncthing-gui.age;

  hasIdentity = name: builtins.pathExists (dir + "/${name}.key.age");
  deviceId = name: lib.removeSuffix "\n" (builtins.readFile (dir + "/${name}.id"));
  hasResolume = name: lib.elem "resolume" (inventory.hosts.${name}.apps or [ ]);

  resolume = lib.elem "resolume" config.production.apps;
  # Other Resolume Macs, plus devices outside the fleet (`resolumePeers` in
  # inventory.nix), which have no fixed address and dial in.
  peers =
    lib.genAttrs
      (lib.filter (name: name != host && hasIdentity name && hasResolume name) (lib.attrNames inventory.hosts))
      (name: let h = inventory.hosts.${name}; in {
        id = deviceId name;
        addresses = [ "tcp://${h.address or h.ip or "${name}.local"}:22000" "dynamic" ];
      })
    // lib.mapAttrs (_: id: { inherit id; addresses = [ "dynamic" ]; }) (inventory.resolumePeers or { });

  folderId = "resolume-arena";
  path = "/Users/${user}/Resolume Arena";
  docsPath = "/Users/${user}/Documents/Resolume Arena";

  # Runs as the operator, before programs.resolume-effects installs into it.
  moveOutOfDocuments = pkgs.writeShellScript "resolume-folder" ''
    set -eu
    real=${lib.escapeShellArg path} docs=${lib.escapeShellArg docsPath}
    [ ! -L "$docs" ] || exit 0
    if [ -d "$docs" ] && [ -e "$real" ]; then
      echo "warning: both $docs and $real exist; merge them by hand, then deploy again" >&2
      exit 0
    elif [ -d "$docs" ]; then
      mv "$docs" "$real"
      echo "moved $docs to $real"
    else
      mkdir -p "$real"
    fi
    mkdir -p "$(dirname "$docs")"
    ln -s "$real" "$docs"
  '';
  ignores = [
    "// Written by modules/syncthing.nix on every deploy."
    "(?d).DS_Store"
    "/Preferences" # this Mac's outputs, DeckLink and devices
    "/Extra Effects" # installed by Nix (programs.resolume-effects)
  ];

  device = name: p: { deviceID = p.id; inherit name; inherit (p) addresses; };
  folder = {
    id = folderId;
    label = "Resolume Arena";
    inherit path;
    type = "sendreceive";
    fsWatcherEnabled = true;
    devices = lib.mapAttrsToList (_: p: { deviceID = p.id; }) peers;
  };

  # Put this Mac's identity in place, then run Syncthing. A new identity
  # starts from a fresh config.xml, so the old one isn't left as a peer.
  serve = pkgs.writeShellScript "syncthing-serve" ''
    set -eu
    home=${lib.escapeShellArg home}
    key=${config.age.secrets.syncthing-key.path}
    cert=${dir + "/${host}.cert.pem"}
    [ -r "$key" ] || { echo "waiting for $key" >&2; sleep 5; exit 1; }
    mkdir -p "$home"
    if ! cmp -s "$cert" "$home/cert.pem"; then
      [ ! -e "$home/config.xml" ] || mv "$home/config.xml" "$home/config.xml.before-identity"
      install -m 0644 "$cert" "$home/cert.pem"
    fi
    cmp -s "$key" "$home/key.pem" || install -m 0600 "$key" "$home/key.pem"
    exec ${pkgs.syncthing}/bin/syncthing serve --no-browser
  '';

  configure = pkgs.writeShellScript "syncthing-config" (''
    set -eu
    xml=${lib.escapeShellArg "${home}/config.xml"}
    key= base=
    # Plain HTTP until the GUI's TLS is on, HTTPS (self-signed) after.
    for _ in $(seq 1 60); do
      [ -f "$xml" ] && key=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$xml")
      for b in https://127.0.0.1:8384 http://127.0.0.1:8384; do
        [ -n "$key" ] && /usr/bin/curl -skf -H "X-API-Key: $key" "$b/rest/system/ping" >/dev/null && { base=$b; break 2; }
      done
      sleep 2
    done
    [ -n "$base" ] || { echo "Syncthing API not up; settings not applied" >&2; exit 1; }
    api() {
      /usr/bin/curl -sSkf -o /dev/null -X "$1" -H "X-API-Key: $key" -H "Content-Type: application/json" \
        "$base/rest/$2" ''${3:+--data "$3"}
    }

    api PATCH config/options ${lib.escapeShellArg (builtins.toJSON { urAccepted = -1; })}
  '' + (if resolume then ''
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: p:
      "api PUT config/devices/${p.id} ${lib.escapeShellArg (builtins.toJSON (device name p))}") peers)}

    # Ignores first, so the first scan never shares what they exclude.
    mkdir -p ${lib.escapeShellArg path}
    printf '%s\n' ${lib.escapeShellArgs ignores} > ${lib.escapeShellArg "${path}/.stignore"}
    api PUT config/folders/${folderId} ${lib.escapeShellArg (builtins.toJSON folder)}
  '' else ''
    api DELETE config/folders/${folderId} 2>/dev/null || true
  '') + lib.optionalString (builtins.pathExists guiSecret) ''

    # Last: changing the GUI restarts its listener (and switches it to HTTPS).
    # Syncthing stores the password bcrypt-hashed.
    api PATCH config/gui "$(${pkgs.jq}/bin/jq -n --arg user ${lib.escapeShellArg user} --rawfile pw ${config.age.secrets.syncthing-gui.path} \
      '{address: "0.0.0.0:8384", useTLS: true, user: $user, password: ($pw | rtrimstr("\n"))}')"
  '');
in
lib.mkMerge [
  {
    environment.systemPackages = [ pkgs.syncthing ];

    launchd.user.agents.syncthing.serviceConfig = {
      ProgramArguments =
        if hasIdentity host then [ "${serve}" ]
        else [ "${pkgs.syncthing}/bin/syncthing" "serve" "--no-browser" ];
      EnvironmentVariables.STNOUPGRADE = "1";
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
    };
  }

  (lib.mkIf resolume {
    system.activationScripts.preActivation.text = ''
      sudo --user=${lib.escapeShellArg user} --set-home ${moveOutOfDocuments}
    '';
  })

  (lib.mkIf (builtins.pathExists guiSecret) {
    age.secrets.syncthing-gui = {
      file = guiSecret;
      owner = user;
      mode = "0400";
    };
  })

  (lib.mkIf (hasIdentity host) {
    age.secrets.syncthing-key = {
      file = dir + "/${host}.key.age";
      owner = user;
      mode = "0400";
    };

    launchd.user.agents.syncthing-config.serviceConfig = {
      ProgramArguments = [ "${configure}" ];
      RunAtLoad = true;
      ProcessType = "Background";
      StandardErrorPath = "/tmp/syncthing-config.log";
    };
  })
]
