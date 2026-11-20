#!/usr/bin/env bash
# Builds the first-boot package for `startosinstall --installpackage`:
# a LaunchDaemon plus firstboot.sh, signed (Developer ID Installer),
# notarized and stapled. See README.md, "Zero-touch reinstall".
#
#   macos-firstboot/build.sh [--token-file FILE] [--unsigned]
#
#   --token-file FILE  GitHub token that can only open issues on this repo,
#                      so each Mac requests its own enrollment. Without it,
#                      enrollment is a manual step. The token is then inside
#                      the .pkg: keep the .pkg on the install USB, never commit
#                      or publish it, and revoke the token if the USB is lost.
#   --unsigned         Skip signing and notarization (layout testing only;
#                      startosinstall refuses an unsigned package).
#
# Environment:
#   SIGN_IDENTITY   default "Developer ID Installer: 7 and Co LLC (JFFQ4Z6YQ5)"
#   NOTARY_PROFILE  notarytool keychain profile, default "notary"
#                   (xcrun notarytool store-credentials notary)
#
# Output: macos-firstboot/build/missionproduction-firstboot-<version>.pkg
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL=org.missionproduction.firstboot
SIGN_IDENTITY=${SIGN_IDENTITY:-"Developer ID Installer: 7 and Co LLC (JFFQ4Z6YQ5)"}
NOTARY_PROFILE=${NOTARY_PROFILE:-notary}

die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

token_file="" signed=1
while [ $# -gt 0 ]; do
  case $1 in
    --token-file) token_file=${2:?--token-file needs a file}; shift ;;
    --unsigned) signed=0 ;;
    -h | --help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument $1" ;;
  esac
  shift
done
if [ -n "$token_file" ]; then
  [ -s "$token_file" ] || die "$token_file is empty or missing"
fi

version=$(date +%Y.%m.%d.%H%M)
rev=$(git rev-parse --short HEAD)
out=macos-firstboot/build
mkdir -p "$out"
pkg="$out/missionproduction-firstboot-$version.pkg"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
root=$work/root
libexec=$root/usr/local/libexec/$LABEL

step "Stage payload"
install -d -m 755 "$root/Library/LaunchDaemons" "$libexec"
install -m 644 "macos-firstboot/$LABEL.plist" "$root/Library/LaunchDaemons/$LABEL.plist"
plutil -lint "$root/Library/LaunchDaemons/$LABEL.plist" >/dev/null
install -m 755 macos-firstboot/firstboot.sh "$libexec/firstboot.sh"
# Non-secret settings, from inventory.nix so they can't drift from the flake.
# shellcheck disable=SC2016  # ${...} is Nix interpolation
nix eval --raw .#inventory --apply 'i: "FB_USER=${i.user}\nFB_PREFIX=${i.generic.prefix}\nFB_REPO=${i.generic.repo}\n"' \
  > "$libexec/firstboot.conf"
chmod 644 "$libexec/firstboot.conf"
cat "$libexec/firstboot.conf"
if [ -n "$token_file" ]; then
  (umask 077; tr -d '[:space:]' < "$token_file" > "$libexec/enroll-token")
  chmod 600 "$libexec/enroll-token"
  echo "enrollment token included (root-only, deleted from the Mac after use)"
else
  echo "no enrollment token: enrollment will be manual"
fi
install -d -m 755 "$work/scripts"
install -m 755 macos-firstboot/scripts/postinstall "$work/scripts/postinstall"
xattr -cr "$root" "$work/scripts"

step "Build component package"
# --ownership recommended: everything installs as root:wheel.
pkgbuild --root "$root" --scripts "$work/scripts" \
  --identifier "$LABEL" --version "$version" \
  --install-location / --ownership recommended \
  "$work/component.pkg"

step "Build product archive"
if [ "$signed" = 1 ]; then
  security find-identity -v -p basic | grep -qF "\"$SIGN_IDENTITY\"" ||
    die "no '$SIGN_IDENTITY' in the keychain (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Installer)"
  productbuild --package "$work/component.pkg" --sign "$SIGN_IDENTITY" --timestamp "$pkg"

  step "Notarize ($NOTARY_PROFILE)"
  result=$(xcrun notarytool submit "$pkg" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
  status=$(printf %s "$result" | plutil -extract status raw - 2>/dev/null || true)
  if [ "$status" != Accepted ]; then
    id=$(printf %s "$result" | plutil -extract id raw - 2>/dev/null || true)
    die "notarization: ${status:-no status} (details: xcrun notarytool log $id --keychain-profile $NOTARY_PROFILE)"
  fi
  xcrun stapler staple "$pkg"
  xcrun stapler validate "$pkg"

  step "Check"
  pkgutil --check-signature "$pkg"
  spctl -a -vv -t install "$pkg"
else
  productbuild --package "$work/component.pkg" "$pkg"
  echo "UNSIGNED: for layout testing only; startosinstall will refuse it"
fi

pkgutil --payload-files "$pkg"
printf '\nbuilt %s (repo %s)\n' "$pkg" "$rev"
