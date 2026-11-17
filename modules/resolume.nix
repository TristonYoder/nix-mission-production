# "This Week" in the Dock next to Arena (Macs with Resolume): opens the week's
# show composition, ~/Resolume Arena/Compositions/YYYY.MM.DD.avc.
#
# A show is named for its first day (2026.11.14 covers the 14th and 15th), so
# the button opens the earliest composition dated yesterday or later -- Monday
# through Sunday the 15th open 2026.11.14, Monday the 16th opens the next one --
# and the most recent one when none is that new. Sync-conflict copies don't
# match the name, so they're never picked.
#
# If Arena already has that show open it's just brought forward; otherwise
# Arena is quit (so it can still ask to save) and reopened on the show.
{ config, lib, pkgs, ... }:

let
  appPath = "/Applications/This Week.app";
  arena = "/Applications/Resolume Arena/Arena.app";

  # Reads the real folder, not ~/Documents (a symlink to it): an app touching
  # ~/Documents makes macOS ask for permission first.
  launcher = pkgs.writeShellScript "this-week" ''
    dir="$HOME/Resolume Arena/Compositions"
    yesterday=''${THIS_WEEK_YESTERDAY:-$(/bin/date -v-1d +%Y.%m.%d)}
    pick= latest=
    for f in "$dir"/[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9].avc; do
      [ -e "$f" ] || continue
      latest=$f
      if [ -z "$pick" ] && [[ ! "$(basename "$f" .avc)" < "$yesterday" ]]; then pick=$f; fi
    done
    pick=''${pick:-$latest}
    if [ -z "$pick" ]; then
      /usr/bin/osascript -e 'display alert "No show composition" message "Nothing named YYYY.MM.DD.avc in ~/Resolume Arena/Compositions."' >/dev/null
      exit 1
    fi

    # Arena records the open composition in its preferences.
    current=$(/usr/bin/sed -n 's/.*name="CurrentCompositionFile"[^>]*value="\([^"]*\)".*/\1/p' \
      "$HOME/Resolume Arena/Preferences/config.xml" 2>/dev/null | /usr/bin/sed 's/&amp;/\&/g')
    same=
    [ -n "$current" ] && [ "$(/bin/realpath "$current" 2>/dev/null)" = "$(/bin/realpath "$pick")" ] && same=1
    running=
    /usr/bin/pgrep -xq Arena && running=1
    [ -z "''${THIS_WEEK_DRY_RUN:-}" ] || { echo "pick=$pick running=$running same=$same"; exit 0; }

    if [ -n "$running" ] && [ -n "$same" ]; then
      exec /usr/bin/open -a ${lib.escapeShellArg arena}
    fi
    if [ -n "$running" ]; then
      /usr/bin/osascript -e 'tell application "Arena" to quit' >/dev/null 2>&1 || true
      while /usr/bin/pgrep -xq Arena; do sleep 0.5; done # until any save prompt is answered
    fi
    exec /usr/bin/open -a ${lib.escapeShellArg arena} "$pick"
  '';

  # A "next" badge for the corner of Arena's icon (Arena's own icon is green).
  badge = pkgs.runCommand "this-week-badge.png" { nativeBuildInputs = [ pkgs.resvg ]; } ''
    cat > badge.svg <<'SVG'
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <circle cx="790" cy="790" r="190" fill="#1d1d22"/>
      <circle cx="790" cy="790" r="160" fill="#ff7a1a"/>
      <path d="M745 695 L840 790 L745 885" fill="none" stroke="#ffffff" stroke-width="56" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
    SVG
    resvg -w 1024 -h 1024 badge.svg "$out"
  '';

  # Arena's icon with the badge, as an .icns (on the Mac: Arena isn't in Nix).
  badgeArenaIcon = pkgs.writeShellScript "this-week-icon" ''
    set -eu
    out=$1 tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    /usr/bin/sips -s format png -Z 1024 ${lib.escapeShellArg "${arena}/Contents/Resources/Arena.icns"} --out "$tmp/base.png" >/dev/null
    ${pkgs.imagemagick}/bin/magick "$tmp/base.png" -resize 1024x1024 ${badge} -composite "$tmp/icon.png"
    mkdir "$tmp/AppIcon.iconset"
    for s in 16 32 128 256 512; do
      /usr/bin/sips -z "$s" "$s" "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_''${s}x''${s}.png" >/dev/null
      /usr/bin/sips -z $((s * 2)) $((s * 2)) "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_''${s}x''${s}@2x.png" >/dev/null
    done
    /usr/bin/iconutil -c icns "$tmp/AppIcon.iconset" -o "$out"
  '';

  bundle = pkgs.runCommand "this-week-app" { } ''
    app="$out/This Week.app/Contents"
    mkdir -p "$app/MacOS" "$app/Resources"
    cp ${launcher} "$app/MacOS/this-week"
    cat > "$app/Info.plist" <<PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleName</key><string>This Week</string>
      <key>CFBundleDisplayName</key><string>This Week</string>
      <key>CFBundleIdentifier</key><string>org.missionproduction.this-week</string>
      <key>CFBundleExecutable</key><string>this-week</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleIconFile</key><string>AppIcon</string>
      <key>LSUIElement</key><true/>
    </dict></plist>
    PLIST
  '';
in
lib.mkIf (lib.elem "resolume" config.production.apps) {
  # Copied (not linked from the read-only store) so it can carry Arena's icon
  # with the badge; redone when Arena's icon is missing at first (not installed).
  # Before the Dock is written (modules/apps.nix, lib.mkAfter).
  system.activationScripts.postActivation.text = ''
    app=${lib.escapeShellArg appPath}
    if [ "$(cat "$app/Contents/.source" 2>/dev/null)" != ${bundle} ] || [ ! -e "$app/Contents/Resources/AppIcon.icns" ]; then
      rm -rf "$app"
      cp -R ${bundle}/'This Week.app' "$app"
      chmod -R u+w "$app"
      echo ${bundle} > "$app/Contents/.source"
      if [ -e ${lib.escapeShellArg "${arena}/Contents/Resources/Arena.icns"} ]; then
        ${badgeArenaIcon} "$app/Contents/Resources/AppIcon.icns" || echo "warning: couldn't badge Arena's icon for This Week" >&2
      fi
      touch "$app"
    fi
  '';
}
