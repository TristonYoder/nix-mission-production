# Generic Macs (inventory.generic): only the baseline every Mac gets (Chrome,
# Google Drive, RustDesk, SSH, Syncthing, wallpaper, pager with no role). No
# apps from a vendor .pkg: those come from the deploy Mac's
# ~/ProductionInstallers, and a generic Mac builds its own system. Give the Mac
# a real role by promoting it to a host in inventory.nix.
{ }
