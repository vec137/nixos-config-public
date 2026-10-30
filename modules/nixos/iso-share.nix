# Read-only file share for handing ISO images to the server's BMC.
#
# Why this exists: the server's BMC (192.168.1.149) can mount an ISO as
# "virtual media" — it shows up to the server as an ordinary USB CD, which is
# the only reliable way to boot installer/WinPE media on that board (Ventoy
# and plain USB sticks proved unreliable there). Most BMCs can pull that ISO
# straight off an NFS or CIFS share instead of making you upload it through
# the web UI, so this module turns the laptop into that share.
#
# Drop the ISO in /srv/iso and point the BMC at:
#   NFS  — 192.168.1.237:/srv/iso   (share) + /win11.iso (image)
#   CIFS — \\192.168.1.237\iso      guest, no password
# Use the wired address 192.168.1.166 instead if the laptop is on ethernet.
#
# Both protocols are exported on purpose: BMC firmware is picky and which one
# works is found by trying. Everything here is read-only and scoped to the
# local subnet. networking.firewall.enable = false on this host, so no ports
# need opening — re-check that if this module is ever reused on a host that
# actually runs a firewall.

{ ... }:

{
  # The directory itself. systemd-tmpfiles creates it on activation, so the
  # share is never exporting a path that doesn't exist yet.
  systemd.tmpfiles.rules = [
    "d /srv/iso 0755 root root -"
  ];

  services.nfs.server = {
    enable = true;
    # `insecure` allows clients connecting from source ports above 1024 —
    # BMC firmware routinely does this, and without it the mount is refused
    # with a bare "permission denied". `all_squash` maps every client to
    # nobody, which is fine for a read-only export.
    exports = ''
      /srv/iso 192.168.1.0/24(ro,sync,insecure,no_subtree_check,all_squash)
    '';
  };

  services.samba = {
    enable = true;
    # nmbd is NetBIOS name resolution — not needed when the BMC is given a
    # bare IP, and it just adds broadcast noise.
    nmbd.enable = false;
    openFirewall = true;

    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "laptop";
        "security" = "user";
        # Accept unauthenticated clients as the guest account instead of
        # rejecting them: BMC virtual-media clients often can't do modern auth.
        "map to guest" = "Bad User";
        "guest account" = "nobody";
        "hosts allow" = "192.168.1. 127.0.0.1";
        "hosts deny" = "0.0.0.0/0";
        # Older BMC firmware speaks only SMB1/NTLMv1, which Samba disables by
        # default for good reason. Kept enabled here because this share is
        # read-only, LAN-scoped and exists for exactly that client. If the BMC
        # turns out to handle SMB2, raise this to "SMB2_10" and drop ntlm auth.
        "server min protocol" = "NT1";
        "ntlm auth" = "yes";
      };

      iso = {
        "path" = "/srv/iso";
        "browseable" = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
      };
    };
  };
}
