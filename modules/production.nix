# Baseline for every production Mac: identity, operator account, remote
# access, and "never surprise anyone during a service" system settings.
{ config, lib, pkgs, inventory, ... }:

let
  cfg = config.production;
  user = inventory.user;
in
{
  options.production = {
    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Machine name from inventory.nix; also its hostname and <name>.local address.";
    };

    label = lib.mkOption {
      type = lib.types.str;
      default = lib.toUpper (lib.replaceStrings [ "-" ] [ " " ] cfg.hostName);
      description = "Human-facing name shown on the wallpaper.";
    };
  };

  config = {
    system.stateVersion = 6;
    nixpkgs.hostPlatform = "aarch64-darwin";
    nixpkgs.config.allowUnfree = true;

    # --- Identity -------------------------------------------------------------
    networking.hostName = cfg.hostName;
    networking.localHostName = cfg.hostName;
    networking.computerName = cfg.label;

    # --- Operator account -----------------------------------------------------
    # The account is created in Setup Assistant; nix-darwin only manages its
    # settings, so it is deliberately not listed in users.knownUsers.
    system.primaryUser = user;
    users.users.${user} = {
      home = "/Users/${user}";
      openssh.authorizedKeys.keys = inventory.deployKeys;
    };

    # --- Remote access --------------------------------------------------------
    # Key-only SSH: the operator password is shared with volunteers, so it must
    # not also be a way in over the network.
    services.openssh.enable = true;
    services.openssh.extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
    '';

    # --- Nix ------------------------------------------------------------------
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      # Lets ./deploy copy prebuilt closures in over SSH.
      trusted-users = [ "root" user ];
    };
    nix.optimise.automatic = true;
    nix.optimise.interval = [{ Weekday = 2; Hour = 3; Minute = 0; }];
    nix.gc = {
      automatic = true;
      interval = [{ Weekday = 2; Hour = 4; Minute = 0; }]; # Tuesday, well clear of services
      options = "--delete-older-than 30d";
    };

    # --- Homebrew (GUI apps; see modules/apps.nix) ----------------------------
    nix-homebrew = {
      enable = true;
      inherit user;
      autoMigrate = true;
    };
    homebrew = {
      enable = true;
      onActivation = {
        cleanup = "zap"; # anything not declared is removed
        autoUpdate = false; # app versions move only when we deploy
        upgrade = false;
      };
    };

    production.apps = [ "chrome" ];
    environment.systemPackages = [ pkgs.git ];

    # --- Never sleep, never lock ----------------------------------------------
    power.sleep = {
      computer = "never";
      display = "never";
      harddisk = "never";
    };
    power.restartAfterPowerFailure = true;

    system.defaults.screensaver.askForPassword = false;
    system.defaults.CustomUserPreferences = {
      "com.apple.screensaver".idleTime = 0;
    };
    system.defaults.NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      NSAutomaticWindowAnimationsEnabled = false;
    };
    system.defaults.loginwindow.GuestEnabled = false;
    system.defaults.dock = {
      autohide = false;
      show-recents = false;
      mru-spaces = false; # keep Spaces in a fixed order
    };
    system.defaults.spaces.spans-displays = false; # each output screen is independent

    # --- No unattended updates ------------------------------------------------
    system.defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;
    system.defaults.CustomSystemPreferences = {
      "com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = true; # still show what's available
        AutomaticDownload = false;
        CriticalUpdateInstall = false;
        ConfigDataInstall = false;
      };
      "com.apple.commerce".AutoUpdate = false;
    };
  };
}
