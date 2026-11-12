# SwiftBar plugin: the machine's name in the menu bar, and the same details as
# the wallpaper card in its dropdown. Prepended by modules/menubar.nix with
# machine-info.sh and: LABEL TITLE LOCATION FUNCTION SUPPORT REVISION.
#
# Runs only when the menu opens; clicking the hostname or an IP copies it.
#
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>
# <swiftbar.runInBash>false</swiftbar.runInBash>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

if [ "${1:-}" = copy ]; then
  printf '%s' "$2" | pbcopy
  exit 0
fi

self="${SWIFTBAR_PLUGIN_PATH:-$0}"
copy() { echo "$1 | bash=$self param1=copy param2=$2 terminal=false tooltip=\"Click to copy\""; }

up_min=$(( up_sec / 60 ))
uptime="$((up_min / 1440))d $((up_min / 60 % 24))h $((up_min % 60))m"
uptime="${uptime#0d }"

echo "$LABEL"
echo "---"
echo "$TITLE"
if [ -n "$LOCATION" ]; then echo "Location: $LOCATION"; fi
if [ -n "$FUNCTION" ]; then echo "Function: $FUNCTION"; fi
echo "---"
copy "Hostname: $host" "$host"
if [ "${#ips[@]}" -eq 0 ]; then echo "IP: none"; fi
for ip in "${ips[@]}"; do copy "IP: $ip" "${ip%% *}"; done
echo "---"
echo "Booted: $booted"
echo "Uptime: $uptime"
echo "$macos${REVISION:+ · config $REVISION}"
if [ -n "$SUPPORT" ]; then
  echo "---"
  echo "Support: $SUPPORT"
fi
