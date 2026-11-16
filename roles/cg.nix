# Graphics machines: SDI/HDMI I/O through Blackmagic hardware, audio on Dante,
# networking through a Sonnet Twin10G card (dual-port 10GBASE-T).
# The presentation app (ProPresenter, Resolume, ...) is chosen per host.
{
  production.apps = [ "desktop-video" "dante-virtual-soundcard" "sonnet-twin10g" ];
}
