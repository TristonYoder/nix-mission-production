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
  # Inter, cut to fixed weights with a slashed zero baked in, so 0 and O
  # can't be confused in IPs and hostnames (ImageMagick can't turn on the
  # font's `zero` feature itself). Display optical size: everything here is
  # large on a 2160 px canvas.
  fonts = pkgs.runCommand "wallpaper-fonts"
    { nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.fonttools ])) ]; }
    ''
      mkdir -p $out
      for w in 400 500 600 900; do
        fonttools varLib.instancer -q ${pkgs.inter}/share/fonts/truetype/InterVariable.ttf \
          wght=$w opsz=32 -o instance.ttf
        python3 ${./slashed-zero.py} instance.ttf $out/Inter-$w.ttf
      done
    '';
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

  # The operator's account picture (login window, lock screen, user menu): a
  # square of the backdrop centred on the logo, so it matches the desktop.
  # The logo sits 520 px wide, 170 px above centre on the 3840x2160 canvas.
  userPicture = pkgs.runCommand "user-picture.jpg"
    { nativeBuildInputs = [ pkgs.imagemagick ]; }
    ''
      magick ${backdrop} -crop 760x760+1540+530 +repage -resize 512x512 \
        -quality 92 $out
    '';

  # Main screen (also the lock screen): the backdrop plus the machine's name
  # under the logo, in Inter Black.
  base = pkgs.runCommand "wallpaper-base.png"
    { nativeBuildInputs = [ pkgs.imagemagick ]; }
    ''
      magick ${backdrop} -gravity center -font ${fonts}/Inter-900.ttf \
        -pointsize 190 -kerning -2 -fill white \
        -annotate +0+260 ${lib.escapeShellArg config.production.label} -depth 8 \
        $out
    '';

  render = pkgs.writeShellApplication {
    name = "production-wallpaper";
    runtimeInputs = [ pkgs.imagemagick pkgs.desktoppr ];
    text = ''
      BACKDROP=${backdrop}
      BASE=${base}
      CARD_FONT=${fonts}/Inter-400.ttf
      CARD_FONT_LABEL=${fonts}/Inter-500.ttf
      CARD_FONT_BOLD=${fonts}/Inter-600.ttf
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
  # macOS shows JPEGPhoto (the image bytes, loaded with dsimport); Picture is
  # the path it came from. Picture doubles as the marker: it names the store
  # path, so the import only reruns when the image changes.
  config.system.activationScripts.postActivation.text = ''
    pic=${userPicture}
    user=${lib.escapeShellArg inventory.user}
    if [ "$(/usr/bin/dscl . -read "/Users/$user" Picture 2>/dev/null | sed -n 's/^Picture: *//p')" != "$pic" ]; then
      echo "setting $user's account picture"
      import=$(mktemp)
      printf '0x0A 0x5C 0x3A 0x2C dsRecTypeStandard:Users 2 dsAttrTypeStandard:RecordName externalbinary:dsAttrTypeStandard:JPEGPhoto\n%s:%s\n' \
        "$user" "$pic" > "$import"
      /usr/bin/dscl . -delete "/Users/$user" JPEGPhoto 2>/dev/null || true
      /usr/bin/dscl . -delete "/Users/$user" Picture 2>/dev/null || true
      if /usr/bin/dsimport "$import" /Local/Default M; then
        /usr/bin/dscl . -create "/Users/$user" Picture "$pic"
      else
        echo "warning: couldn't set $user's account picture" >&2
      fi
      rm -f "$import"
    fi
  '';

  config.launchd.user.agents.wallpaper = {
    command = "${render}/bin/production-wallpaper";
    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 60;
    };
  };
}
