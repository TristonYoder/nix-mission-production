# Graphics machines: SDI/HDMI I/O through Blackmagic hardware, audio on Dante.
# The presentation app (ProPresenter, Resolume, ...) is chosen per host.
{ lib, ... }:

{
  production.apps = [ "desktop-video" "dante-virtual-soundcard" ];

  # Wired only: a second network over WiFi gives the Mac a competing default
  # route (the old CG3 sat on the admin network this way).
  production.wifi.mode = lib.mkDefault "off";
}
