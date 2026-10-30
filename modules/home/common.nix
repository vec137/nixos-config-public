{ pkgs, ... }:
{
  home = {
    username = "nix";
    homeDirectory = "/home/nix";
    stateVersion = "25.05";

    # Base nixpkgs tracks the nixos-26.05 stable branch (see flake.nix) while
    # home-manager itself moves faster and only tags releases against
    # nixos-unstable, so this version mismatch is permanent by design here,
    # not a drift to fix — silence the warning it prints on every rebuild.
    enableNixpkgsReleaseCheck = false;

    # CLI/headless tooling — useful with or without a GUI session, so this
    # is what a future non-desktop host would still want.
    packages = with pkgs; [
      fastfetch
      gotop
      curlFull
      dnsutils
      net-tools
      samba
      cifs-utils
      unzip
      unrar
      trash-cli
      go
      jdk
      gcc
      glibc
      grc
      bc
      jq
      socat
      ntfs3g
      usbutils
      ripgrep
      lm_sensors
      cachix
      timer
      powershell
      img2pdf
      file
      claude-code
      nh
      nix-output-monitor
      python3
      fzf
    ];

    sessionVariables = {
      "EDITOR" = "nvim";
      "PAGER" = "bat --style=plain --color=always";
      # HTTPS_PROXY used to be set globally here, but any app reads it the
      # same way Claude Code does - cassette (Yandex Music client) was
      # silently routing its API traffic through the xray tunnel too,
      # which made it flap whenever that tunnel hiccuped. Scoped down to
      # just the `claude` fish function instead (see modules/home/fish.nix).
      # Lets `nh os`/`nh home` find this flake from any directory, instead
      # of needing --flake /home/nix/.nix or cd'ing here first every time.
      "NH_FLAKE" = "/home/nix/.nix";
    };

    shell.enableFishIntegration = true;
  };

  news.display = "silent";
}
