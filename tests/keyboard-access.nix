{ pkgs, config }:
let
  user = config.users.users.hotaru;
  hasGroup = name: builtins.elem name user.extraGroups
    || builtins.elem user.name config.users.groups.${name}.members;
in
assert config.hardware.uinput.enable;
assert builtins.elem "uinput" config.boot.kernelModules;
assert hasGroup "input";
assert hasGroup "uinput";
assert config.services.xserver.xkb.layout == "jp";
assert config.services.xserver.xkb.variant == "";
pkgs.runCommand "dotfiles-keyboard-access-check" {} ''
  # Validate the merged rules, including hardware.uinput's later assignment.
  rules=${pkgs.writeText "keyboard-udev.rules" config.services.udev.extraRules}
  grep -F 'KERNEL=="event*", GROUP="input", MODE="0660"' "$rules"
  grep -F 'SUBSYSTEM=="misc", KERNEL=="uinput", MODE="0660", GROUP="uinput"' "$rules"
  if grep 'KERNEL=="uinput".*GROUP="input"' "$rules"; then
    echo 'Conflicting legacy uinput rule' >&2
    exit 1
  fi
  touch "$out"
''
