{ inputs, pkgs, ... }:
{
  home = {
    # GUI/Wayland desktop utilities that don't fit a specific profile theme:
    # theming, screenshot/clipboard/notification tooling, GTK/Qt plumbing.
    packages = with pkgs; [
      pywalfox-native
      base16-schemes
      tinty
      addwater
      wl-clipboard
      brightnessctl
      playerctl
      rpi-imager
      awww
      pywal
      pamixer
      slurp
      xdg-user-dirs
      wf-recorder
      grimblast
      gnome-calculator
      gnome-text-editor
      gnome-power-manager
      zenity
      nautilus
      file-roller
      glib
      loupe
      bibata-cursors
      libnotify
      gtklock
      gtklock-playerctl-module
      eww
      hyprpicker
      iio-hyprland
      iio-niri
      gdk-pixbuf
      gobject-introspection
      adw-gtk3
      papirus-icon-theme
      gpu-screen-recorder
      polkit_gnome
      gnome-control-center
      hyprmagnifier
      qt5.qtwayland
      libsForQt5.qt5ct
      inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
      xwayland-satellite-unstable
      xhost
    ];

    sessionVariables = {
      "WLR_NO_HARDWARE_CURSORS" = "1";
      "MOZ_ENABLE_WAYLAND" = "1";
      "EGL_PLATFORM" = "wayland";
      "MOZ_DISABLE_RDD_SANDBOX" = "1";
      "QT_QPA_PLATFORM" = "wayland";
      "QT_QPA_PLATFORMTHEME" = "qt5ct";
      "XCURSOR_THEME" = "Bibata-Modern-Classic";
      "XCURSOR_SIZE" = "19";
      "NIXOS_OZONE_WL" = "1";
      "GIO_EXTRA_MODULES" = "${pkgs.gvfs}/lib/gio/modules";
      "_JAVA_AWT_WM_NONREPARENTING" = "1";
    };

    pointerCursor = {
      enable = true;
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 19;
      gtk.enable = true;
      x11.enable = true;
      hyprcursor.enable = true;
    };

    file = {
      ".icons/Papirus-Dark".source = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark";
      ".icons/Papirus".source = "${pkgs.papirus-icon-theme}/share/icons/Papirus";
      ".icons/Papirus-Light".source = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Light";

      ".local/share/icons/Papirus-Dark".source = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark";
      ".local/share/icons/Papirus".source = "${pkgs.papirus-icon-theme}/share/icons/Papirus";
      ".local/share/icons/Papirus-Light".source = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Light";
    };
  };
}
