{ pkgs, ... }:
{
  home.packages = with pkgs; [
    thunderbird
    obsidian
    onlyoffice-desktopeditors
    libreoffice-qt
    # WordCraft — третий офисный редактор, но не из nixpkgs: пакет лежит у нас
    # в pkgs/wordcraft.nix и приходит через overlay-local (см. flake.nix).
    # Прекомпилированный релиз, ~270 МБ на замыкание.
    wordcraft
  ];
}
