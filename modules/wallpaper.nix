# Wallpaper: a dark gradient with the logo and the machine's name in the
# centre, plus an info card (location, function, hostname, IPs, boot time,
# uptime, support number), so anyone at the rack knows which Mac they're
# looking at and how to reach it.
#
# The background is fixed at build time. The card is drawn at login by a user
# agent that re-checks every minute and redraws only when its text changes.
# Only the main screen gets the name and card; other screens (often show
# outputs) get just the logo.
{ config, lib, pkgs, inventory, ... }:

let
  cfg = config.production.wallpaper;
  fonts = "${pkgs.roboto-mono}/share/fonts/truetype";
  rev = config.system.configurationRevision;

  # Every screen: dark gradient (or `background`) with the logo in white.
  backdrop = pkgs.runCommand "wallpaper-backdrop.png"
    { nativeBuildInputs = [ pkgs.imagemagick ]; }
    ''
      magick ${if cfg.background == null then ''
          -size 3840x2160 -define gradient:angle=135 gradient:'#2b2c30-#050506' \
          \( -size 3840x2160 radial-gradient:'rgba(255,255,255,0.06)-rgba(255,255,255,0)' \) \
          -compose screen -composite -compose over \
          -attenuate 0.6 +noise Uniform''
        else "${cfg.background} -resize 3840x2160^ -gravity center -extent 3840x2160"} \
        \( ${../assets/logo.png} -background white -alpha remove -colorspace gray -negate \
           -resize 520x520 -alpha copy -fill white -colorize 100 \) \
        -gravity center -geometry +0-170 -composite -depth 8 \
        $out
    '';

  # Main screen (also the lock screen): the backdrop plus the machine's name
  # under the logo. Archivo Expanded Black: the variable font pinned to
  # wdth=125 wght=900 with fonttools' varLib.instancer (OFL, see assets/fonts).
  base = pkgs.runCommand "wallpaper-base.png"
    { nativeBuildInputs = [ pkgs.imagemagick ]; }
    ''
      magick ${backdrop} -gravity center -font ${../assets/fonts/ArchivoExpanded-Black.ttf} \
        -pointsize 160 -kerning 4 -fill white \
        -annotate +0+260 ${lib.escapeShellArg config.production.label} -depth 8 \
        $out
    '';

  render = pkgs.writeShellApplication {
    name = "production-wallpaper";
    runtimeInputs = [ pkgs.imagemagick pkgs.desktoppr ];
    text = ''
      BACKDROP=${backdrop}
      BASE=${base}
      CARD_FONT=${fonts}/RobotoMono-Regular.ttf
      CARD_FONT_BOLD=${fonts}/RobotoMono-Bold.ttf
      TITLE=${lib.escapeShellArg cfg.title}
      LOCATION=${lib.escapeShellArg (toString cfg.location)}
      FUNCTION=${lib.escapeShellArg cfg.function}
      SUPPORT_FILE=${lib.escapeShellArg config.age.secrets.support.path}
      REVISION=${lib.escapeShellArg (if rev == null then "" else lib.substring 0 7 rev)}
    '' + builtins.readFile ./machine-info.sh + builtins.readFile ./wallpaper-card.sh;
  };
in
{
  options.production.wallpaper = {
    background = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = if builtins.pathExists ../assets/wallpaper.jpg then ../assets/wallpaper.jpg else null;
      description = "Background image (default: assets/wallpaper.jpg if present, else a dark gradient).";
    };
    title = lib.mkOption {
      type = lib.types.str;
      default = inventory.wallpaper.title;
    };
    location = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    function = lib.mkOption {
      type = lib.types.str;
      default = config.production.label;
    };
  };

  # `command` runs it through /bin/sh. macOS's background-item check keys on
  # the executable's code identity: a store path changes every deploy and
  # pops an "App Background Activity" notification each time; /bin/sh never
  # changes.
  config.launchd.user.agents.wallpaper = {
    command = "${render}/bin/production-wallpaper";
    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 60;
    };
  };
}
