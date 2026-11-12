# Draws the info card onto the main screen's wallpaper. Prepended by
# modules/wallpaper.nix with machine-info.sh and: BACKDROP (other screens)
# BASE (main screen) CARD_FONT CARD_FONT_BOLD TITLE LOCATION FUNCTION SUPPORT
# REVISION (empty = left out). Also draws a faint hostname/build tag in the
# bottom-right corner, beside the Dock, so it shows up in screenshots.
#
# Runs at login and every minute after; it only redraws when the card's text
# changes (new IP, reboot, deploy, uptime ticking over an hour), so nothing
# flickers during a service.

state="$HOME/Library/Caches/production-wallpaper"
mkdir -p "$state"

row() { printf '%-9s %s' "$1" "$2"; }   # monospace: values line up

# Live values come from machine-info.sh (prepended). Uptime in whole hours
# only, so the card redraws hourly rather than every minute.
up_h=$(( up_sec / 3600 ))
if [ "$up_h" -ge 24 ]; then uptime="$((up_h / 24))d $((up_h % 24))h"
elif [ "$up_h" -ge 1 ]; then uptime="${up_h}h"
else uptime="<1h"; fi

ip_rows=""
for ip in "${ips[@]}"; do ip_rows+="${ip_rows:+$'\n'}$(row IP "$ip")"; done
[ -n "$ip_rows" ] || ip_rows="$(row IP none)"

# --- Card text ----------------------------------------------------------------

sections=()
who=""
[ -n "$LOCATION" ] && who="$(row Location "$LOCATION")"
[ -n "$FUNCTION" ] && who+="${who:+$'\n'}$(row Function "$FUNCTION")"
[ -n "$who" ] && sections+=("$who")
sections+=("$(row Hostname "$host")"$'\n'"$ip_rows")
system="$(row Booted "$booted")"$'\n'"$(row Uptime "$uptime")"$'\n'"$(row System "$macos")"
[ -n "$REVISION" ] && system+=" · $REVISION"
sections+=("$system")
[ -n "$SUPPORT" ] && sections+=("$(row Support "$SUPPORT")")

text="$TITLE"$'\n'"$(printf '%s\n' "${sections[@]}")"
current="$(cat "$state/current" 2>/dev/null || true)"
# Skip unless the text changed or the main screen isn't showing our card
# (someone changed it, or macOS dropped it).
if [ "$text" = "$(cat "$state/text" 2>/dev/null)" ] && [ -e "$current" ] &&
   [ "$(desktoppr 0)" = "$current" ]; then
  exit 0
fi

# --- Render -------------------------------------------------------------------
# Card is drawn at 4K scale to match BASE. macOS caches wallpapers by path, so
# every render gets a new file name.

width=1100
# One margin (4K px) for the corner tag's right and bottom, and the card's
# right edge. The card sits one margin above the tag.
margin=72
tag_size=34
# Small corner tag right of the Dock, so screenshots show which Mac and build.
tag="$host${REVISION:+ · $REVISION}"
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
  -gravity southeast -geometry "+$margin+$((margin * 2 + tag_size))" -composite \
  -font "$CARD_FONT" -pointsize "$tag_size" -fill 'rgba(255,255,255,0.5)' \
  -annotate "+$margin+$margin" "$tag" \
  -depth 8 "$out"

# Screen 0 has the menu bar. Each screen is set exactly once: setting "all"
# then "main" races, since macOS applies them asynchronously.
desktoppr 0 "$out"
i=1
while desktoppr "$i" "$BACKDROP" 2>/dev/null; do i=$((i + 1)); done

[ -n "$current" ] && [ "$current" != "$out" ] && rm -f "$current"
printf '%s' "$out" > "$state/current"
printf '%s' "$text" > "$state/text"
