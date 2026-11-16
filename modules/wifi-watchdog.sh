# One pass of the WiFi watchdog (launchd runs it on every network change):
#   wired port with internet -> WiFi off
#   anything else            -> WiFi on
# "Internet" is tested through each wired port itself (ping -b), so a port
# that only carries Dante, or has link but a dead uplink, doesn't count.

log() { echo "$(/bin/date '+%F %T') $*"; }

ports=$(/usr/sbin/networksetup -listallhardwareports)
wifi=$(printf '%s\n' "$ports" | /usr/bin/awk '/^Hardware Port: Wi-Fi/{getline; print $2}')
if [ -z "$wifi" ]; then
  exit 0
fi

# Every other hardware port except Thunderbolt bridging (never an uplink).
wired=$(printf '%s\n' "$ports" | /usr/bin/awk '
  /^Hardware Port:/ { skip = ($0 ~ /Wi-Fi|Bluetooth|Thunderbolt Bridge|Thunderbolt [0-9]/) }
  /^Device:/ && !skip { print $2 }')

online() {
  for host in $TARGETS; do
    /sbin/ping -b "$1" -c 1 -t 3 -q "$host" >/dev/null 2>&1 && return 0
  done
  return 1
}

uplink=""
for dev in $wired; do
  info=$(/sbin/ifconfig "$dev" 2>/dev/null) || continue
  case "$info" in *"status: active"*) ;; *) continue ;; esac
  case "$info" in *"inet "*) ;; *) continue ;; esac
  if online "$dev"; then
    uplink=$dev
    break
  fi
done

power=$(/usr/sbin/networksetup -getairportpower "$wifi" | /usr/bin/awk '{print $NF}')

if [ -n "$uplink" ]; then
  if [ "$power" = "On" ]; then
    /usr/sbin/networksetup -setairportpower "$wifi" off
    log "internet on $uplink: WiFi ($wifi) off"
  fi
else
  if [ "$power" != "On" ]; then
    /usr/sbin/networksetup -setairportpower "$wifi" on
    log "no wired internet: WiFi ($wifi) on"
  fi
fi
