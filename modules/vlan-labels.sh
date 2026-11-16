# Names each port's network service after the network its address is in,
# e.g. "Dante Primary (VLAN 910)", or "Staff WiFi" for an entry without an id.
# VLANS (prepended) holds one "id|name|network|prefix" line per network.
# Runs on every network change.
#   address in a known VLAN -> that VLAN's name
#   address elsewhere       -> back to the hardware port's own name
#   no address (unplugged)  -> left alone, so the port keeps its last label

log() { echo "$(/bin/date '+%F %T') $*"; }

ip2int() {
  local IFS=.
  # shellcheck disable=SC2086
  set -- $1
  echo $(( ($1 << 24) | ($2 << 16) | ($3 << 8) | $4 ))
}

vlan_for() {
  local addr id name net prefix mask
  addr=$(ip2int "$1")
  while IFS='|' read -r id name net prefix; do
    [ -n "$name" ] || continue
    mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    if (( (addr & mask) == ($(ip2int "$net") & mask) )); then
      if [ -n "$id" ]; then echo "$name (VLAN $id)"; else echo "$name"; fi
      return
    fi
  done <<< "$VLANS"
}

# "service|port|device" for every service bound to a hardware port. A leading
# "(*) " marks a disabled service; the name itself doesn't include it.
services=$(/usr/sbin/networksetup -listnetworkserviceorder | /usr/bin/awk '
  /^\([0-9*]+\) / { sub(/^\([0-9*]+\) /, ""); name = $0; next }
  /^\(Hardware Port: / {
    line = $0
    sub(/^\(Hardware Port: /, "", line); sub(/\)$/, "", line)
    n = split(line, f, ", Device: ")
    if (n == 2 && f[2] != "") print name "|" f[1] "|" f[2]
  }')

taken=$(printf '%s\n' "$services" | /usr/bin/cut -d'|' -f1)

while IFS='|' read -r service port dev; do
  [ -n "$dev" ] || continue
  case "$port" in Bluetooth*|"Thunderbolt Bridge"|Thunderbolt\ [0-9]*) continue ;; esac

  addr=$(/usr/sbin/ipconfig getifaddr "$dev" 2>/dev/null || true)
  [ -n "$addr" ] || continue

  want=$(vlan_for "$addr")
  [ -n "$want" ] || want=$port
  [ "$service" = "$want" ] && continue

  # Two ports on one VLAN (or a leftover service): service names must be unique.
  if printf '%s\n' "$taken" | /usr/bin/grep -qxF "$want"; then
    want="$want - $dev"
    [ "$service" = "$want" ] && continue
  fi

  if /usr/sbin/networksetup -renamenetworkservice "$service" "$want"; then
    log "$dev ($addr): \"$service\" -> \"$want\""
    taken=$(printf '%s\n' "$taken" | /usr/bin/grep -vxF "$service"; echo "$want")
  fi
done <<< "$services"
