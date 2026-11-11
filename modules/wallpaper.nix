# Wallpaper that names the machine, so anyone at the rack knows which Mac
# they're looking at. Rendered at build time, applied at login.
{ config, lib, pkgs, ... }:

let
  cfg = config.production.wallpaper;
  label = config.production.label;

  image = pkgs.runCommand "wallpaper-${config.production.hostName}.png"
    { nativeBuildInputs = [ pkgs.imagemagick ]; }
    ''
      magick ${if cfg.background == null then "-size 3840x2160 xc:${lib.escapeShellArg cfg.color}"
               else "${cfg.background} -resize 3840x2160^ -gravity center -extent 3840x2160"} \
        -gravity center -font ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf \
        -pointsize 360 -fill ${lib.escapeShellArg cfg.textColor} \
        -annotate +0+0 ${lib.escapeShellArg label} \
        $out
    '';
in
{
  options.production.wallpaper = {
    background = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional background image; the label is drawn on top.";
    };
    color = lib.mkOption {
      type = lib.types.str;
      default = "#111111";
      description = "Solid background colour when no image is set.";
    };
    textColor = lib.mkOption {
      type = lib.types.str;
      default = "#ffffff";
    };
  };

  config.launchd.user.agents.wallpaper.serviceConfig = {
    ProgramArguments = [ "${pkgs.desktoppr}/bin/desktoppr" "all" "${image}" ];
    RunAtLoad = true;
  };
}
