# Generated via dconf2nix: https://github.com/gvolpe/dconf2nix
{ lib, ... }:

with lib.hm.gvariant;

{
  dconf.settings = {
    "org/gnome/desktop/wm/preferences".button-layout = ":minimize,maximize,close";
    # "org/gnome/desktop/input-sources" = {
    #   mru-sources = [ (mkTuple [ "xkb" "us" ]) ];
    #   sources = [ (mkTuple [ "xkb" "us+dvp" ]) (mkTuple [ "xkb" "jp" ]) ];
    #   xkb-options = [ "terminate:ctrl_alt_bksp" ];
    # };

    "org/virt-manager/virt-manager/connections" = {
      autoconnect = ["qemu:///system"];
      uris = ["qemu:///system"];
    };

    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      show-battery-percentage = true;
    };

    "org/gnome/shell/extensions/clipboard-history" = {
      toggle-menu = [ "<Super>v" ];
    };

    "org/gnome/shell/extensions/runcat" = {
      displaying-items = "character-and-percentage";
      idle-threshold = 5;
    };

    "org/gnome/shell/keybindings" = {
      toggle-message-tray = [];
    };

    "org/gnome/desktop/peripherals/mouse" = {
      left-handed = false;
      speed = -0.3618677042801557;
    };

    "org/gnome/desktop/peripherals/touchpad" = {
      send-events = "disabled";
      two-finger-scrolling-enabled = true;
    };

    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-type = "nothing";
    };
  };
}
