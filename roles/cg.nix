# Graphics machines: SDI/HDMI I/O through Blackmagic hardware, audio on Dante.
# The presentation app (ProPresenter, Resolume, ...) is chosen per host.
{ lib, ... }:

{
  production.apps = [ "desktop-video" "dante-virtual-soundcard" ];

  # Wired only: a second network over WiFi gives the Mac a competing default
  # route (the old CG3 sat on the admin network this way).
  production.wifi.mode = lib.mkDefault "off";

  # Desktop Video's updater agent is removed (modules/apps.nix), and with it the
  # prompt to update card firmware after a driver change. Firmware older than
  # the driver leaves the card without its audio devices, so report it on every
  # deploy. Flashing stays manual: it needs a full shutdown afterwards.
  system.activationScripts.postActivation.text = ''
    tool="/Library/Application Support/Blackmagic Design/Blackmagic DeckLink/Desktop Video Updater.app/Contents/MacOS/DesktopVideoUpdateTool"
    if [ -x "$tool" ] && "$tool" -l 2>/dev/null | grep -q "out of date"; then
      echo "warning: Blackmagic card firmware is out of date:" >&2
      "$tool" -l 2>/dev/null | grep -B1 "out of date" | sed 's/^/  /' >&2
      echo "  fix outside service: sudo \"$tool\" -u -a, then shut down (not restart)" >&2
    fi
  '';
}
