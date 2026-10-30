{ inputs, pkgs, ... }:
{
  # Network/pentest tooling, VPN/proxy clients, and forensics/mobile-recon
  # utilities. Not needed on a plain desktop or server host.
  #
  # Base nixpkgs is the stable release branch (see flake.nix), but this
  # profile wants fast-moving tooling on its latest version (protocol/exploit
  # support), so it pulls from pkgs-unstable (nixos-unstable, via
  # overlay-bleeding in flake.nix) instead of the pinned stable set.
  home.packages = with pkgs.pkgs-unstable; [
    openconnect
    ocproxy
    throne
    v2rayn
    proxychains-ng
    xray
    tun2proxy
    netdiscover
    openvpn
    wireshark
    nmap
    plantuml
    srecord
    binwalk
    exiftool
    pngcheck
    unixtools.fsck
    dosfstools
    foremost
    scrcpy
    revanced-cli
    pixelflasher
    apktool
    byedpi
    android-tools
    python313Packages.impacket
  ] ++ [
    inputs.burp.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
