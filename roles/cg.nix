# Graphics machines: SDI/HDMI I/O through Blackmagic hardware, audio on Dante,
# networking through a Sonnet Twin10G card (dual-port 10GBASE-T).
# The presentation app (ProPresenter, Resolume, ...) is chosen per host.
{ lib, ... }:

{
  production.apps = [ "desktop-video" "dante-virtual-soundcard" "sonnet-twin10g" ];
  production.pager.role = "CG";

  # Lyric Flip blend mode into ~/Documents/Resolume Arena/Extra Effects, plus the
  # Dynamic Lyric ProPresenter theme in ~/Documents/7 & Co Resolume Effects.
  # Reinstalled on each deploy, so versions only move with flake.lock.
  programs.resolume-effects.enable = true;

  # Wired only: a second network over WiFi gives the Mac a competing default
  # route (the old CG3 sat on the admin network this way).
  production.wifi.mode = lib.mkDefault "off";

  # Card firmware follows the Desktop Video driver. The vendor's updater agent
  # (an operator prompt at login) is removed in modules/apps.nix, so the deploy
  # flashes instead: firmware only goes stale when we bump the driver pin, and
  # deploys never run in a blackout window. Firmware older than the driver
  # leaves the card without its audio devices.
  #
  # Flashing changes nothing until the card loses power, so the running show
  # is unaffected; the new firmware loads after a full SHUT DOWN (a restart
  # keeps the card powered). That step stays deliberate, so the deploy only
  # says so. /var/run is cleared at boot, so the marker means "flashed, not yet
  # power-cycled" and stops a re-flash on every deploy in between.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    tool="/Library/Application Support/Blackmagic Design/Blackmagic DeckLink/Desktop Video Updater.app/Contents/MacOS/DesktopVideoUpdateTool"
    flashed=/var/run/production-blackmagic-firmware-flashed
    if [ -x "$tool" ]; then
      if [ -e "$flashed" ]; then
        echo "warning: Blackmagic firmware was updated; SHUT DOWN this Mac (not restart) to load it" >&2
      elif "$tool" -l 2>/dev/null | grep -q "out of date"; then
        echo "Blackmagic card firmware is out of date; updating:"
        "$tool" -l 2>/dev/null | grep -B1 "out of date" | sed 's/^/  /'
        rc=0
        out=$("$tool" -u -a -q 2>&1) || rc=$?
        printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | sed 's/^/  /' || true
        if [ "$rc" -eq 0 ]; then
          touch "$flashed"
          echo "warning: Blackmagic firmware updated; SHUT DOWN this Mac (not restart) to load it" >&2
        else
          echo "warning: Blackmagic firmware update failed; run: sudo \"$tool\" -u -a" >&2
        fi
      fi
    fi
  '';

  # Fonts for graphics, on top of Inter (everywhere). Drop files in fonts/cg/.
  production.fontDirs = [ ../fonts/cg ];

  # Creative Team share from the NAS at /Volumes/Creative Team (modules/nas.nix).
  production.nas.enable = true;
}
