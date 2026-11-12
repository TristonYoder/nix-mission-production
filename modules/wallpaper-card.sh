# Draws the info card onto the main screen's wallpaper. Prepended by
# modules/wallpaper.nix with: BACKDROP (other screens) BASE (main screen)
# CARD_FONT CARD_FONT_BOLD TITLE LOCATION FUNCTION SUPPORT REVISION
# (empty = line left out).
#
# Runs at login and every minute after; it only redraws when the card's text
# changes (new IP, reboot, deploy, uptime ticking over an hour), so nothing
# flickers during a service.

state="$HOME/Library/Caches/production-wallpaper"
mkdir -p "$state"

# --- Live values --------------------------------------------------------------

row() { printf '%-9s %s' "$1" "$2"; }   # monospace: values line up

host="$(scutil --get LocalHostName).local"

# One row per interface with an address, named the way System Settings names
# it: "IP        10.0.0.12 (Ethernet Adapter (en3))".
ips=""
while IFS='|' read -r port dev; do
  addr="$(ipconfig getifaddr "$dev" 2>/dev/null || true)"
  [ -n "$addr" ] && ips+="${ips:+$'\n'}$(row IP "$addr ($port)")"
done < <(networksetup -listallhardwareports | awk -F': ' '
  /^Hardware Port:/ { port = $2 }
  /^Device:/        { print port "|" $2 }')
[ -n "$ips" ] || ips="$(row IP none)"

boot_sec="$(sysctl -n kern.boottime | sed -E 's/.*sec = ([0-9]+),.*/\1/')"
booted="$(date -r "$boot_sec" '+%a %b %-d, %-I:%M %p')"
# Whole hours only, so the card redraws hourly rather than every minute.
up_h=$(( ($(date +%s) - boot_sec) / 3600 ))
if [ "$up_h" -ge 24 ]; then uptime="$((up_h / 24))d $((up_h % 24))h"
elif [ "$up_h" -ge 1 ]; then uptime="${up_h}h"
else uptime="<1h"; fi
macos="macOS $(sw_vers -productVersion)"

# --- Card text ----------------------------------------------------------------

sections=()
who=""
[ -n "$LOCATION" ] && who="$(row Location "$LOCATION")"
[ -n "$FUNCTION" ] && who+="${who:+$'\n'}$(row Function "$FUNCTION")"
[ -n "$who" ] && sections+=("$who")
sections+=("$(row Hostname "$host")"$'\n'"$ips")
system="$(row Booted "$booted")"$'\n'"$(row Uptime "$uptime")"$'\n'"$(row System "$macos")"
[ -n "$REVISION" ] && system+=" · $REVISION"
sections+=("$system")
[ -n "$SUPPORT" ] && sections+=("$(row Support "$SUPPORT")")

text="$TITLE"$'\n'"$(printf '%s\n' "${sections[@]}")"
if [ "$text" = "$(cat "$state/text" 2>/dev/null)" ] && [ -e "$(cat "$state/current" 2>/dev/null)" ]; then
  exit 0
fi

# --- Render -------------------------------------------------------------------
# Card is drawn at 4K scale to match BASE. macOS caches wallpapers by path, so
# every render gets a new file name.

width=1100
args=(-background none -fill white -font "$CARD_FONT_BOLD" -pointsize 50
      -size "${width}x" "caption:$TITLE" -font "$CARD_FONT" -pointsize 38)
for s in "${sections[@]}"; do
  args+=(\( -size "${width}x34" xc:none \)
         \( -size "${width}x2" "xc:rgba(255,255,255,0.35)" \)
         \( -size "${width}x26" xc:none \)
         \( -size "${width}x" -interline-spacing 10 "caption:$s" \))
done

out="$state/wallpaper-$(date +%s).png"
magick "$BASE" \
  \( "${args[@]}" -append \
     -bordercolor none -border 56 \
     \( +clone -alpha transparent -fill 'rgba(0,0,0,0.62)' \
        -draw 'roundrectangle 0,0 %[fx:w-1],%[fx:h-1] 32,32' \) \
     +swap -composite \) \
  -gravity southeast -geometry +260+200 -composite \
  "$out"

desktoppr all "$BACKDROP"
desktoppr main "$out"

old="$(cat "$state/current" 2>/dev/null || true)"
[ -n "$old" ] && [ "$old" != "$out" ] && rm -f "$old"
printf '%s' "$out" > "$state/current"
printf '%s' "$text" > "$state/text"
