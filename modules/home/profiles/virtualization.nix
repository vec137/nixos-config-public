{ pkgs, ... }:
{
  # Network simulation (GNS3) and VM/remote-access tooling.
  home.packages = with pkgs; [
    spice-vdagent
    remmina
    gns3-server
    gns3-gui
    inetutils
    ubridge
    vpcs
    dynamips
  ];
}
