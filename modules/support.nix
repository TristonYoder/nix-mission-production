# Support phone number, encrypted at rest in secrets/support.age and read at
# runtime by the wallpaper and menu bar. Keeping it out of inventory.nix means
# the real support line is never published in the repo.
#
# Edit it with:
#   cd secrets && nix develop .. -c agenix -e support.age -i ~/.ssh/agenix
{ inventory, ... }:
{
  age.secrets.support = {
    file = ../secrets/support.age;
    # The wallpaper and SwiftBar agents run as the operator, not root.
    owner = inventory.user;
    mode = "0400";
  };
}
