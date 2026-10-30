{ pkgs, ... }:
let
  # discord-canary launches via its .desktop file (Exec=DiscordCanary),
  # not through a shell, so the fish-function trick used for `claude`
  # (see modules/home/fish.nix) can't intercept it — wrap the actual
  # binaries instead so HTTPS_PROXY is set no matter how it's launched.
  discord-canary-proxied = pkgs.symlinkJoin {
    name = "discord-canary-proxied-${pkgs.discord-canary.version}";
    paths = [ pkgs.discord-canary ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/DiscordCanary --set HTTPS_PROXY http://127.0.0.1:6080
      wrapProgram $out/bin/discordcanary --set HTTPS_PROXY http://127.0.0.1:6080
    '';
  };
in
{
  home.packages = with pkgs; [
    ayugram-desktop
    element-desktop
    discord-canary-proxied
    teamspeak6-client
    keepassxc
  ];
}
