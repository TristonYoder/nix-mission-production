#!/bin/bash
# First boot of a freshly installed Mac, run as root by
# /Library/LaunchDaemons/org.missionproduction.firstboot.plist (installed by
# the package from build.sh, through `startosinstall --installpackage`).
#
# Waits for the network, Setup Assistant and the operator's first login, then:
#   clt       Xcode Command Line Tools, headless
#   nix       Nix (the same multi-user installer ./deploy bootstrap uses)
#   hostname  <prefix>-<last 6 hex digits of en0's MAC>
#   switch    first nix-darwin activation of darwinConfigurations.<prefix>
#             (Homebrew comes with it, through nix-homebrew)
#   enroll    open a GitHub issue with this Mac's SSH host key; an Action turns
#             it into a PR that adds the key and re-keys the secrets
# then removes itself. Each step leaves a marker in $STATE and is skipped on a
# rerun; a failed step is retried at the next boot or in 15 minutes (the
# daemon's StartInterval). Log: /var/log/firstboot.log.
#
# Rerun by hand: sudo launchctl kickstart -k system/org.missionproduction.firstboot
set -euo pipefail

LABEL=org.missionproduction.firstboot
LIBEXEC=/usr/local/libexec/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
STATE=/var/db/$LABEL
LOG=/var/log/firstboot.log
LOCK=/var/run/$LABEL.lock # cleared at boot, so a power cut never leaves it stuck

export HOME=/var/root USER=root
export PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
die() { log "error: $*"; exit 1; }

# --- Config (non-secret, written by build.sh from inventory.nix) -------------
FB_USER="" FB_PREFIX="" FB_REPO=""
while IFS='=' read -r k v; do
  case $k in
    FB_USER) FB_USER=$v ;;
    FB_PREFIX) FB_PREFIX=$v ;;
    FB_REPO) FB_REPO=$v ;;
  esac
done < "$LIBEXEC/firstboot.conf"
[ -n "$FB_USER" ] && [ -n "$FB_PREFIX" ] && [ -n "$FB_REPO" ] || die "incomplete $LIBEXEC/firstboot.conf"
TOKEN_FILE=$LIBEXEC/enroll-token

mkdir -p "$STATE"
chmod 700 "$STATE"
done_() { [ -e "$STATE/$1.done" ]; }
mark() { date '+%Y-%m-%d %H:%M:%S' > "$STATE/$1.done"; log "step $1: done"; }

# One run at a time (launchd won't overlap runs, but a manual run might).
if ! mkdir "$LOCK" 2>/dev/null; then
  log "another run is in progress; exiting"
  exit 0
fi
notify_failure=0
finish() {
  local rc=$?
  rm -rf "$LOCK"
  if [ "$rc" -ne 0 ] && [ "$notify_failure" = 1 ]; then
    log "failed (exit $rc); retrying at next boot or in 15 minutes"
    notify "Mac setup failed" "Retrying automatically. Details: $LOG"
  fi
}
trap finish EXIT

console_uid() { stat -f %u /dev/console; }
console_user() { stat -f %Su /dev/console; }

# Notification in the operator's session (no-op before anyone logs in).
notify() { # <title> <message>
  local u uid
  u=$(console_user)
  [ "$u" = "$FB_USER" ] || return 0
  uid=$(console_uid)
  launchctl asuser "$uid" sudo -u "$u" /usr/bin/osascript \
    -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' \
    "$1" "$2" >/dev/null 2>&1 || true
}

# --- Wait for the machine to be usable --------------------------------------
wait_for() { # <description> <command...>
  local what=$1 n=0
  shift
  until "$@"; do
    [ $((n % 60)) -eq 0 ] && log "waiting for $what"
    n=$((n + 1))
    sleep 10
  done
}

net_up() { curl -sfI --max-time 10 https://github.com >/dev/null 2>&1; }
setup_done() { [ -e /var/db/.AppleSetupDone ]; }
operator_logged_in() {
  local u
  u=$(console_user)
  case $u in
    root | loginwindow | _mbsetupuser | "") return 1 ;;
    "$FB_USER") return 0 ;;
    *)
      [ -e "$STATE/warned-user" ] || {
        log "warning: '$u' is logged in; waiting for '$FB_USER' (create it in Setup Assistant)"
        touch "$STATE/warned-user"
      }
      return 1 ;;
  esac
}

log "starting (macOS $(sw_vers -productVersion))"
wait_for "Setup Assistant to finish" setup_done
wait_for "$FB_USER to log in" operator_logged_in
wait_for "the network (github.com)" net_up
notify_failure=1

# --- 1. Xcode Command Line Tools --------------------------------------------
if ! done_ clt; then
  if ! xcode-select -p >/dev/null 2>&1; then
    log "step clt: installing Command Line Tools"
    marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    touch "$marker"
    # Label format varies by release ("...Xcode-16.4", "...Xcode 27.2-27.2"):
    # sort on the version and keep the newest (same as ./deploy bootstrap).
    label=$(softwareupdate -l 2>/dev/null |
      sed -n 's/^\* Label: \(Command Line Tools for Xcode[- ]\(.*\)\)$/\2|\1/p' |
      sort -t '|' -k1,1V | tail -1 | cut -d '|' -f2)
    if [ -n "$label" ]; then
      softwareupdate -i "$label" || true
    fi
    rm -f "$marker"
  fi
  xcode-select -p >/dev/null 2>&1 || die "Command Line Tools did not install"
  mark clt
fi

# --- 2. Nix ------------------------------------------------------------------
if ! done_ nix; then
  if [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
    log "step nix: installing Nix"
    tmp=$(mktemp -d)
    curl -sSfL https://nixos.org/nix/install -o "$tmp/install"
    # Multi-user install; as root and with --yes it needs no prompts.
    sh "$tmp/install" --daemon --yes --no-channel-add
    rm -rf "$tmp"
  fi
  /nix/var/nix/profiles/default/bin/nix --version >/dev/null || die "nix is not usable"
  mark nix
fi

# --- 3. Hostname -------------------------------------------------------------
# The hardware address (networksetup), not the private WiFi one, so the name
# survives a reinstall.
mac=$(networksetup -getmacaddress en0 | awk '{print $3}' | tr -d ':' | tr 'A-F' 'a-f')
[[ $mac =~ ^[0-9a-f]{12}$ ]] || die "could not read en0's MAC address"
HOST="$FB_PREFIX-${mac:6:6}"
if ! done_ hostname; then
  scutil --set ComputerName "$HOST"
  scutil --set LocalHostName "$HOST"
  scutil --set HostName "$HOST"
  log "step hostname: $HOST"
  mark hostname
fi

# --- 4. First nix-darwin switch ---------------------------------------------
# nix-darwin isn't installed yet, so build the system and activate it the way
# ./deploy does. Built from the exact commit main points at: a `github:` ref
# with no commit can come from a stale cache.
if ! done_ switch; then
  rev=$(git ls-remote "https://github.com/$FB_REPO" refs/heads/main | cut -f1)
  [ -n "$rev" ] || die "could not resolve main on github.com/$FB_REPO"
  flake="github:$FB_REPO/$rev"
  log "step switch: building $flake#$FB_PREFIX"
  system=$(nix --extra-experimental-features 'nix-command flakes' build \
    "$flake#darwinConfigurations.$FB_PREFIX.system" --no-link --print-out-paths)
  # nix-darwin refuses to take over /etc files the Nix installer wrote.
  if [ ! -e /run/current-system ]; then
    for f in /etc/bashrc /etc/zshrc /etc/nix/nix.conf; do
      if [ -e "$f" ] && [ ! -L "$f" ]; then mv "$f" "$f.before-nix-darwin"; fi
    done
  fi
  nix-env -p /nix/var/nix/profiles/system --set "$system"
  "$system/activate"
  # nix-homebrew keeps /opt/homebrew itself root's and hands the operator
  # what brew writes to.
  [ -x /opt/homebrew/bin/brew ] && [ "$(stat -f %Su /opt/homebrew/Caskroom 2>/dev/null)" = "$FB_USER" ] ||
    die "Homebrew is missing, or /opt/homebrew/Caskroom is not owned by $FB_USER"
  mark switch
fi

# --- 5. Enrollment -----------------------------------------------------------
# The host key is what agenix decrypts secrets with. Until it is in
# secrets/host-keys and the secrets are re-keyed, RustDesk, WiFi and the other
# secret-backed modules stay idle. The token (if the package has one) can only
# open issues on the repo; .github/workflows/enroll-host.yml does the rest.
if ! done_ enroll; then
  [ -s /etc/ssh/ssh_host_ed25519_key.pub ] || ssh-keygen -A
  key=$(awk '{print $1, $2}' /etc/ssh/ssh_host_ed25519_key.pub)
  [[ $key =~ ^ssh-ed25519\ [A-Za-z0-9+/]+=*$ ]] || die "unexpected host key format"
  fp=$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')
  log "step enroll: host key $key ($fp)"
  if [ -s "$TOKEN_FILE" ]; then
    model=$(sysctl -n hw.model)
    os=$(sw_vers -productVersion)
    # Every value is validated above or comes from the OS, so no JSON escaping
    # is needed. The token goes in through a header file, never argv or the log.
    body="<!-- enroll-host v1 -->\\nhost: $HOST\\nkey: $key\\nfingerprint: $fp\\nmodel: $model\\nmacos: $os"
    hdr=$(mktemp)
    chmod 600 "$hdr"
    printf 'Authorization: Bearer %s\n' "$(tr -d '[:space:]' < "$TOKEN_FILE")" > "$hdr"
    resp=$(mktemp)
    code=$(curl -sS -o "$resp" -w '%{http_code}' -X POST \
      -H @"$hdr" -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      "https://api.github.com/repos/$FB_REPO/issues" \
      -d "{\"title\":\"Enroll $HOST\",\"body\":\"$body\"}") || code=000
    rm -f "$hdr"
    if [ "$code" != 201 ]; then
      log "GitHub answered $code: $(head -c 300 "$resp")"
      rm -f "$resp"
      die "could not open the enrollment issue"
    fi
    url=$(sed -n 's/.*"html_url": *"\([^"]*\/issues\/[0-9]*\)".*/\1/p' "$resp" | head -1)
    rm -f "$resp"
    log "enrollment requested: $url"
    notify "Mac set up as $HOST" "Waiting for its enrollment PR to be merged. Remote support starts after that."
  else
    log "no enrollment token in this package: add the key above as secrets/host-keys/$HOST.pub and re-key"
    notify "Mac set up as $HOST" "Needs manual enrollment: host key in $LOG"
  fi
  mark enroll
fi

# --- Done: remove ourselves --------------------------------------------------
mark complete
log "complete; removing the first-boot daemon"
notify_failure=0
rm -f "$PLIST" "$TOKEN_FILE"
rm -rf "$LIBEXEC" "$LOCK"
launchctl bootout "system/$LABEL" 2>/dev/null || true
