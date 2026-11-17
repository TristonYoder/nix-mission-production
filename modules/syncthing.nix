# Syncthing on every Mac, running as the operator from login. Every Mac with
# Resolume keeps ~/Documents/Resolume Arena in sync with the others, apart from
# the per-machine parts in `ignores`.
#
# Each Mac's identity lives in secrets/syncthing (written by
# `./deploy bootstrap`): <host>.id and <host>.cert.pem are public, the key is
# agenix-encrypted. A Mac without one yet runs Syncthing with a throwaway
# identity and syncs nothing.
#
# The settings below are reapplied at login and on every deploy that changes
# them; anything else can still be changed in the web UI at
# http://127.0.0.1:8384 on the Mac.
#
# From nixpkgs rather than the Homebrew cask: the Nix build has Syncthing's
# self-upgrade compiled out, so it only changes when a deploy changes it.
{ config, lib, pkgs, inventory, ... }:

let
  user = config.system.primaryUser;
  host = config.production.hostName;
  dir = ../secrets/syncthing;
  home = "/Users/${user}/Library/Application Support/Syncthing";

  hasIdentity = name: builtins.pathExists (dir + "/${name}.key.age");
  deviceId = name: lib.removeSuffix "\n" (builtins.readFile (dir + "/${name}.id"));
  hasResolume = name: lib.elem "resolume" (inventory.hosts.${name}.apps or [ ]);

  resolume = lib.elem "resolume" config.production.apps;
  peers = lib.filter (name: name != host && hasIdentity name && hasResolume name)
    (lib.attrNames inventory.hosts);

  folderId = "resolume-arena";
  path = "/Users/${user}/Documents/Resolume Arena";
  ignores = [
    "// Written by modules/syncthing.nix on every deploy."
    "(?d).DS_Store"
    "/Preferences" # this Mac's outputs, DeckLink and devices
    "/Extra Effects" # installed by Nix (programs.resolume-effects)
  ];

  device = name: let h = inventory.hosts.${name}; in {
    deviceID = deviceId name;
    inherit name;
    addresses = [ "tcp://${h.address or h.ip or "${name}.local"}:22000" "dynamic" ];
  };
  folder = {
    id = folderId;
    label = "Resolume Arena";
    inherit path;
    type = "sendreceive";
    fsWatcherEnabled = true;
    devices = map (name: { deviceID = deviceId name; }) peers;
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
    key=
    for _ in $(seq 1 60); do
      [ -f "$xml" ] && key=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$xml")
      [ -n "$key" ] && /usr/bin/curl -sf -H "X-API-Key: $key" http://127.0.0.1:8384/rest/system/ping >/dev/null && break
      key=
      sleep 2
    done
    [ -n "$key" ] || { echo "Syncthing API not up; settings not applied" >&2; exit 1; }
    api() {
      /usr/bin/curl -sSf -o /dev/null -X "$1" -H "X-API-Key: $key" -H "Content-Type: application/json" \
        "http://127.0.0.1:8384/rest/$2" ''${3:+--data "$3"}
    }

    api PATCH config/options ${lib.escapeShellArg (builtins.toJSON { urAccepted = -1; })}
  '' + (if resolume then ''
    ${lib.concatMapStringsSep "\n" (name:
      "api PUT config/devices/${deviceId name} ${lib.escapeShellArg (builtins.toJSON (device name))}") peers}

    # Ignores first, so the first scan never shares what they exclude.
    mkdir -p ${lib.escapeShellArg path}
    printf '%s\n' ${lib.escapeShellArgs ignores} > ${lib.escapeShellArg "${path}/.stignore"}
    api PUT config/folders/${folderId} ${lib.escapeShellArg (builtins.toJSON folder)}
  '' else ''
    api DELETE config/folders/${folderId} 2>/dev/null || true
  ''));
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
