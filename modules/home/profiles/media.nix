{ pkgs, ... }:
{
  home.packages = with pkgs; [
    krita
    moonlight-qt
    qbittorrent
    djvu2pdf
    totem
    yt-dlp
    mpv
    vlc
    ffmpeg-full
    flac
    imagemagick
    pavucontrol
    cassette
  ];
}
