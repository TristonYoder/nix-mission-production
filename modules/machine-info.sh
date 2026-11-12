# Live facts about this Mac, shared by the wallpaper card and the menu bar
# plugin. Sets: host, ips (array of "10.0.0.12 (Wi-Fi)"), booted, up_sec, macos.

host="$(scutil --get LocalHostName).local"

# Every interface with an address, named the way System Settings names it.
ips=()
while IFS='|' read -r port dev; do
  addr="$(ipconfig getifaddr "$dev" 2>/dev/null || true)"
  if [ -n "$addr" ]; then ips+=("$addr ($port)"); fi
done < <(networksetup -listallhardwareports | awk -F': ' '
  /^Hardware Port:/ { port = $2 }
  /^Device:/        { print port "|" $2 }')

boot_sec="$(sysctl -n kern.boottime | sed -E 's/.*sec = ([0-9]+),.*/\1/')"
booted="$(date -r "$boot_sec" '+%a %b %-d, %-I:%M %p')"
up_sec=$(( $(date +%s) - boot_sec ))
macos="macOS $(sw_vers -productVersion)"
