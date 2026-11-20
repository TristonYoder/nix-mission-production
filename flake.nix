{
  description = "Live production Macs";

  inputs = {
    # Stable channels: show machines should only change when we decide they change.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    # Only for packages whose macOS support postdates 26.05 (pam_rssh).
    # Drop at 26.11.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Our FFGL plugins for Resolume (Lyric Flip) + the matching ProPresenter theme.
    resolume-effects = {
      url = "github:TristonYoder/resolume-effects";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nix-darwin, nix-homebrew, agenix, resolume-effects }:
    let
      inventory = import ./inventory.nix;
      system = "aarch64-darwin";

      mkHost = name: host:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = {
            inherit inventory;
            pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
          };
          modules = [
            nix-homebrew.darwinModules.nix-homebrew
            agenix.darwinModules.default
            resolume-effects.darwinModules.default
            ./modules
            ./roles/${host.role}.nix
            {
              production.hostName = name;
              production.apps = host.apps or [ ];
              production.network.ip = host.ip or null;
              system.configurationRevision = self.rev or self.dirtyRev or null;
            }
            (nixpkgs.lib.optionalAttrs (host ? label) { production.label = host.label; })
            { production.wallpaper = builtins.intersectAttrs { location = null; function = null; } host; }
          ] ++ nixpkgs.lib.optional (host ? config) host.config;
        };
    in
    {
      # Plus the shared profile every not-yet-named Mac runs (macos-firstboot/,
      # modules/generic.nix). Its name is set at first boot, not here.
      darwinConfigurations = builtins.mapAttrs mkHost inventory.hosts // {
        ${inventory.generic.prefix} = mkHost inventory.generic.prefix {
          inherit (inventory.generic) role;
          label = "MISSION PRODUCTION";
          config.production.generic = true;
        };
      };

      # Read by ./deploy (addresses, blackout windows, roles).
      inherit inventory;

      devShells.${system}.default = nixpkgs.legacyPackages.${system}.mkShell {
        packages = [ agenix.packages.${system}.default nixpkgs.legacyPackages.${system}.syncthing ];
      };
    };
}
