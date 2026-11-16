{ pkgs, ... }:
let
  # L2TP/IPsec needs IKEv1. Nixpkgs strongSwan 6.1 builds without it by default.
  # Limit this custom build to the RTX830 NetworkManager plugin.
  strongswanIkev1 = pkgs.strongswan.overrideAttrs (old: {
    configureFlags = (old.configureFlags or [ ]) ++ [ "--enable-ikev1" ];
  });

  # NixOS 26.05 pins the vulnerable 1.52.0 release. Upstream 1.52.6 fixes
  # CVE-2026-19624, CVE-2026-75131 and CVE-2026-75883/93337. Revisit when nixpkgs
  # carries a fixed version; do not silently revert to the older package.
  networkmanagerL2tp = (pkgs.networkmanager-l2tp.override {
    strongswan = strongswanIkev1;
  }).overrideAttrs (_: {
    version = "1.52.6";
    name = "NetworkManager-l2tp-gnome-1.52.6";
    src = pkgs.fetchurl {
      url = "https://github.com/nm-l2tp/NetworkManager-l2tp/releases/download/1.52.6/NetworkManager-l2tp-1.52.6.tar.xz";
      # SHA-256 published for the official 1.52.6 release asset.
      hash = "sha256-9jzHlAKXWa7uW87xD5ghZZ5iPMwPEbIqGeBuuyVjQOA=";
    };
  });

  client = pkgs.writeShellApplication {
    name = "rtx830-vpn";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      getent
      iproute2
      networkmanager
    ];
    text = builtins.readFile ../scripts/rtx830-vpn;
  };
in
{
  networking.networkmanager.plugins = [ networkmanagerL2tp ];

  # NetworkManager-l2tp writes the transient IPsec PSK to this directory at
  # connection time. Keep it writable by root, not a read-only Nix store path;
  # neither the PSK nor the generated secrets file belongs in this repo.
  systemd.tmpfiles.rules = [ "d /etc/ipsec.d 0700 root root -" ];

  # The NetworkManager L2TP plugin manages its own strongSwan and xl2tpd
  # processes. Do not enable global strongswan/xl2tpd services in parallel.
  environment.systemPackages = with pkgs; [
    client
    strongswanIkev1
    xl2tpd
    ppp
    networkmanagerapplet # nm-connection-editor for the local-only profile
  ];

  # The actual server/gateway and authentication details live only in the
  # local NetworkManager profile, never in a Nix expression or the Nix store.
  # Remove the route pin when the VPN is disconnected via GUI or by failure.
  networking.networkmanager.dispatcherScripts = [
    {
      source = pkgs.writeShellScript "rtx830-vpn-dispatcher" ''
        if [ "''${CONNECTION_ID:-}" = "rtx830-vpn" ] && [ "''${2:-}" = "vpn-down" ]; then
          ${client}/bin/rtx830-vpn route-down
        fi
      '';
      type = "basic";
    }
  ];
}
