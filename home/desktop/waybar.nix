{ config, pkgs, ... }:
let
  # These user-profile binaries are installed by the sibling desktop module.
  bin = "${config.home.profileDirectory}/bin";
in {
  programs.waybar = {
    enable = true;
    systemd = {
      enable = true;
      targets = [ "wayland-session@Hyprland.target" ];
    };
    style = builtins.readFile ./waybar.css;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 30;
      spacing = 6;
      modules-left = [ "custom/launcher" "hyprland/workspaces" ];
      modules-center = [ "clock" ];
      modules-right = [ "custom/keyboard" "custom/clipboard" "network" "pulseaudio" "battery" "tray" ];
      "custom/launcher" = {
        format = "Apps";
        tooltip-format = "Win+Space / Win+D";
        on-click = "${bin}/desktop-launcher";
      };
      "hyprland/workspaces" = { format = "{name}"; on-click = "activate"; };
      clock = { format = "{:%m/%d (%a)  %H:%M}"; tooltip-format = "{:%Y-%m-%d}"; };
      "custom/keyboard" = {
        exec = "${bin}/keyboard-profile json";
        return-type = "json";
        interval = 2;
        on-click = "${bin}/keyboard-profile toggle";
      };
      "custom/clipboard" = {
        exec = "${bin}/desktop-clipboard status";
        format = "Clip: {}";
        interval = 2;
        on-click = "${bin}/desktop-clipboard-menu";
        on-click-right = "${bin}/desktop-clipboard toggle";
        tooltip-format = "Win+V: history; Win+Shift+V: privacy pause";
      };
      network = {
        format-wifi = "Wi-Fi {signalStrength}%";
        format-ethernet = "LAN";
        format-disconnected = "Offline";
        tooltip-format = "{ifname}: {ipaddr}";
      };
      pulseaudio = {
        format = "Vol {volume}%";
        format-muted = "Muted";
        on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
      };
      battery = {
        states = { warning = 25; critical = 10; };
        format = "Bat {capacity}%";
        format-charging = "Charging {capacity}%";
        format-full = "Full";
      };
      tray.spacing = 8;
    };
  };
}
