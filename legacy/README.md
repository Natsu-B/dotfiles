# Legacy keyboard configuration

These files preserve the previous XKB us(dvp)-based setup. They are not imported
by NixOS or Home Manager. Do not run them together with the new keyboard profiles.

- `xremap-us-dvp.yml`: previous root `config.yml`, preserved without modification.
- `custom_dvorak.xkb`: previous `nixos/custom_dvorak.xkb`, preserved without modification.

The active implementation is `home/desktop/generate_xremap.py`, using a fixed XKB
`jp` base in both desktop environments. See `../DESKTOP.md`.
