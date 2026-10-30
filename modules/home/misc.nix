{ pkgs, inputs, ... }: 
let
    vpn = import ../nixos/vpn/settings.nix;
    spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.system};
in
{
    imports = [ 
    	inputs.spicetify-nix.homeManagerModules.spicetify
    ];

	dconf.settings = {
		"org/gnome/desktop/interface" = {
			"cursor-theme" = "Bibata-Modern-Classic";
			"gtk-theme" = "adw-gtk3";
			"icon-theme" = "Papirus";
			"font-name" = "JetBrains Mono Regular 11";
			"color-scheme" = "prefer-dark";
		};
	};
	services.kdeconnect.enable = true;
	services.kdeconnect.indicator = true;
	services.syncthing.enable = true;
	services.playerctld.enable = true;

	xdg.enable = true;
	xdg.portal.enable = true;
	xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk pkgs.xdg-desktop-portal-gnome pkgs.xdg-desktop-portal-hyprland ];
	xdg.portal.config = {
      niri = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
        # niri реализует DBus-интерфейс org.gnome.Mutter.ScreenCast нативно
        # (совместимость с gnome-shell), поэтому для скринкаста нужен именно
        # gnome-бэкенд портала - gtk/hyprland этот интерфейс не отдают.
        "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ];
      };
      common = {
        default = [ "gtk" ];
      };
    };
	xdg.mimeApps = {
		enable = true;
		defaultApplications = {
				"text/html" = "librewolf.desktop";
				"x-scheme-handler/http" = "librewolf.desktop";
				"x-scheme-handler/https" = "librewolf.desktop";
				"x-scheme-handler/about" = "librewolf.desktop";
				"x-scheme-handler/unknown" = "librewolf.desktop";
				"image/png" = "org.gnome.Loupe.desktop";
				"image/jpeg" = "org.gnome.Loupe.desktop";
				"application/pdf" = "librewolf.desktop";
				"video/mp4" = "org.gnome.Totem.desktop";
				"video/x-matroska" = "org.gnome.Totem.desktop";
				"video/x-ms-wmv" = "org.gnome.Totem.desktop";
		};
	};
	xdg.configFile."mimeapps.list".force = true;
	xdg.userDirs = {
		enable = true;
		createDirectories = true;
		setSessionVariables = true;
	};

	programs.eza.enable = true;
	programs.bat.enable = true;
	programs.librewolf = {
		enable = true;
		package = pkgs.librewolf;
		profiles.my-profile = {
			isDefault = true;
			id = 0;
			path = "yrkka9g3.default";
			# firefox-gnome-theme itself lives unmanaged in
			# chrome/firefox-gnome-theme/ (installed by hand, keeps its own
			# updater) -- this just re-imports it and overrides one of its
			# CSS variables afterwards so the header bar/tab strip reads
			# darker than the theme's own default (#2e2e32).
			# Because it is unmanaged, a librewolf bump can break chrome
			# styling until that checkout is refreshed from upstream master
			# by hand (158.0 dropped .urlbarView-body-outer and left the
			# urlbar suggestions transparent) -- see docs/repo-notes.md.
			userChrome = ''
				@import "firefox-gnome-theme/userChrome.css";

				:root {
					--gnome-headerbar-background: #1F1E25 !important;
				}
			'';
			# Firefox 157 (29.09.2026) shipped the "Nova" redesign by default --
			# curved tabs with a "fire" palette (warm glow around the active
			# tab, colourful background behind tab icons). LibreWolf picked
			# this up in its v157 rebase (02.10.2026). firefox-gnome-theme
			# hasn't fully caught up yet (upstream issues #1113 "Broken on
			# Firefox 156" and #1127 "Follow-up fixes for 157", both open as
			# of 05.10.2026 -- Firefox 156 renamed/dropped a bunch of the
			# chrome IDs and CSS custom properties the theme's selectors
			# depend on), so Nova's native colours leak through instead of
			# being overridden. Upstream ships a kill switch for exactly
			# this: pref() form here because it needs to land in user.js
			# before first run, not a userChrome.css hack -- Nova changes
			# markup/tokens, not just colours, so CSS alone can't fully
			# revert it. Mozilla has flagged this pref as temporary and
			# likely to be removed in a future release.
			settings."browser.nova.enabled" = false;
		};
		# Settings-only clone of my-profile (prefs/extensions/bookmarks, no
		# logins/cookies/history -- copied by hand into
		# ~/.librewolf/ru-certs.default, not managed by home-manager itself)
		# meant to hold Russian root CAs (e.g. Минцифры) without trusting them
		# in the main profile. Import the cert via this profile's own
		# about:preferences#privacy -> Certificates -> Manage Certificates --
		# LibreWolf ignores the system NSS store (security.enterprise_roots is
		# off), so it has to go into this profile's cert9.db directly, which
		# also naturally scopes it to just this profile.
		profiles.ru-certs = {
			isDefault = false;
			id = 1;
			path = "ru-certs.default";
			userChrome = ''
				@import "firefox-gnome-theme/userChrome.css";

				:root {
					--gnome-headerbar-background: #1F1E25 !important;
				}
			'';
			# See my-profile above -- same Nova/firefox-gnome-theme mismatch.
			settings."browser.nova.enabled" = false;
		};
		# Dedicated profile driven by the firefox-devtools MCP server (see
		# modules/home/browser-mcp.nix). Kept separate from my-profile on
		# purpose: a browser MCP server inherits every logged-in session in
		# whatever profile it drives, so this one starts empty and should only
		# ever hold the logins a given automation task actually needs.
		profiles.mcp = {
			isDefault = false;
			id = 2;
			path = "mcp.default";
		};
	};
	programs.htop = {
		enable = true;
		settings = {
			show_cpu_usage = 1;
			show_cpu_frequency = 1;
			show_cpu_temperature = 1;
		};
	};
	programs.git = {
		enable = true;
		settings = { 
			user.name = "vec137";
			user.email = "you@example.com";
			init.defaultBranch = "master"; 
			pull.rebase = "false";
		};
	};
	programs.ssh = {
		enable = true;
		enableDefaultConfig = false;
		settings = {
			"*" = { 
				forwardAgent = false; 
				addKeysToAgent = "no"; 
				compression = false; 
				serverAliveInterval = 0; 
				serverAliveCountMax = 3; 
				hashKnownHosts = false;
				userKnownHostsFile = "~/.ssh/known_hosts"; 
				controlMaster = "no"; 
				controlPath = "~/.ssh/master-%r@%n:%p"; 
				controlPersist = "no"; 
			};
			"github.com" = {
				identityFile = "~/.nix/ssh/github";
			};
			"gitlab.com" = {
				identityFile = "~/.nix/ssh/id_gitlab";
			};
			"artix" = {
				hostname = "192.168.0.18";
				user = "artix";
				identityFile = "~/.nix/ssh/id_artix";
			};
			"client-ubuntu" = {
				hostname = "192.168.122.206";
				user = "root";
				identityFile = "~/.nix/ssh/client-ubuntu";
			};
			"server-ubuntu" = {
				hostname = "192.168.122.165";
				user = "root";
				identityFile = "~/.nix/ssh/server-ubuntu";
			};
			"inferno" = {
				hostname = "203.0.113.60";
				port = 41467;
				user = "root";
				identityFile = "~/.nix/ssh/vps";
			};
			"aeza" = {
				hostname = "203.0.113.61";
				port = 41467;
				user = "vps";
				identityFile = "~/.nix/ssh/id_rsa_vps";
			};
			"openwrt" = {
				hostname = "openwrt.lan";
				port = 22;
				user = "root";
				identityFile = "~/.nix/ssh/openwrt";
			};
			"waicore" = {
				hostname = "203.0.113.20";
				port = 41467;
				user = "vps";
				identityFile = "~/.nix/ssh/waicore";
			};
			"home" = {
				hostname = "homeassistant.lan";
				port = 22;
				user = "hassio";
				identityFile = "~/.nix/ssh/hass";
			};
			"hyperhdr" = {
				hostname = "hyperhdr.lan";
				port = 22;
				user = "pi";
				identityFile = "~/.nix/ssh/hyperhdr";
			};
			"server" = {
				hostname = "server.lan";
				port = 22;
				user = "nix";
				identityFile = "~/.nix/ssh/server";
			};
			# Временный второй сервер (hosts/forge). Ключ тот же, что у
			# server: это клиентский ключ ноутбука, он прописан в
			# authorizedKeys обоих хостов.
			#
			# hostname — короткое `forge`, а не `forge.lan` и не адрес: записи в
			# зоне `lan` заводит dnsmasq роутера из DHCP-аренды, а `search lan`
			# (тоже от DHCP) заставляет резолвер сам дописать домен. Адрес при
			# этом может меняться, имя — нет.
			#
			# ВАЖНО про `ssh forge.lan`: он НЕ подхватит эти настройки. Шаблоны
			# `Host` сверяются с тем, что НАБРАНО в командной строке, а не с
			# результатом разрешения имени, поэтому `Host forge` на `forge.lan`
			# не срабатывает — identityFile не подставляется, а предлагать ssh
			# нечего (приватных ключей в ~/.ssh/ нет вообще, все живут в
			# ~/.nix/ssh/), и ответ будет «Permission denied (publickey)».
			# Правильное имя для набора здесь одно — `forge`.
			"forge" = {
				hostname = "forge.lan";
				port = 22;
				user = "nix";
				identityFile = "~/.nix/ssh/server";
			};
			# VPS из флейка (hosts/ru-edge, hosts/nl-exit). Адреса и порт —
			# в modules/nixos/vpn/settings.nix. До nl-exit напрямую из дома не
			# достучаться (провайдер режет ответы с его IP) — через ru-edge.
			# Ключ — vpn.deployKeys (публичные половины в settings.nix), приватная
			# половина — ssh/vps_deploy_202610 (gitignored).
			"ru-edge" = {
				hostname = vpn.hosts.ru-edge;
				port = vpn.sshPort;
				user = "nix";
				identityFile = "~/.nix/ssh/vps_deploy_202610";
				identitiesOnly = true;
			};
			"nl-exit" = {
				hostname = vpn.hosts.nl-exit;
				port = vpn.sshPort;
				user = "nix";
				identityFile = "~/.nix/ssh/vps_deploy_202610";
				identitiesOnly = true;
				proxyJump = "ru-edge";
			};
		};
	};
	programs.cava = {
		enable = true;
		settings = {
			general.framerate = 60;
			general.bar_width = 6;
			general.autosens = 1;
			# color.foreground = "blue";
			color.theme = "noctalia";
		};
	};
	programs.alacritty = {
		enable = true;
		settings = {
			font = {
				normal.family = "JetBrainsMono";
				normal.style = "Regular";
				size = 10.5;
			};
			general.import = [ "~/.config/alacritty/themes/noctalia.toml" ];
		};
	};

	# ranger с превью картинок — чтобы было чем проверить графику в ghostty
	# (modules/home/ghostty.nix).
	#
	# preview_images_method = "kitty" — это kitty graphics protocol: ranger
	# сам гонит картинку escape-последовательностями в терминал, без ueberzug
	# и X11-оверлеев (на Wayland оверлейный путь толком не работает), ghostty
	# протокол реализует полностью. Внутри tmux превью не будет: ranger при
	# первом показе опрашивает терминал (a=q) и ждёт ответа, tmux его не
	# пробрасывает — ranger это предусмотрел и молча отключает превью
	# (ImgDisplayUnsupportedException). Проверять надо в чистом окне ghostty.
	# Альтернативный метод "sixel" тут не годится: sixel'а у ghostty нет.
	#
	# Сам пакет из nixpkgs уже тянет pillow (без него kitty-метод падает с
	# "previews using kitty graphics require PIL"), imagemagick, highlight и
	# w3m. extraPackages попадают в PATH обёртки ranger — их дёргает штатный
	# scope.sh для всего, что не картинка: видео, pdf, метаданные, архивы.
	programs.ranger = {
		enable = true;
		settings = {
			preview_images = true;
			preview_images_method = "kitty";
		};
		extraPackages = with pkgs; [
			ffmpegthumbnailer   # кадр из видео
			poppler-utils       # pdftoppm — первая страница pdf
			mediainfo           # метаданные медиафайлов
			atool               # содержимое архивов
		];
	};

    programs.spicetify = {
		enable = true;
		enabledExtensions = with spicePkgs.extensions; [
			adblockify
			hidePodcasts
			shuffle # shuffle+ (special characters are sanitized out of extension names)
			keyboardShortcut
		];
		theme = spicePkgs.themes.sleek;
		colorScheme = "TokyoNight";
		wayland = true;
    };

	programs.noctalia.enable = true;

	programs.tmux = {
		enable = true;
		keyMode = "vi";
		mouse = true;
		# Префикс здесь штатный, C-b. C-a стоит ТОЛЬКО на сервере
		# (hosts/server/home.nix) - расхождение сознательное, а не забытая
		# правка: на ноутбуке tmux запускается локально, и C-a остаётся за
		# shell/nvim в значении "в начало строки".
		extraConfig = ''
			set -g focus-events on

			bind -T copy-mode-vi v send -X begin-selection
			bind -T copy-mode-vi y send -X copy-pipe-and-cancel "wl-copy"

			bind h select-pane -L
			bind j select-pane -D
			bind k select-pane -U
			bind l select-pane -R

			bind -r H resize-pane -L 5
			bind -r J resize-pane -D 5
			bind -r K resize-pane -U 5
			bind -r L resize-pane -R 5
		'';

		plugins = [ 
			{
				plugin = pkgs.tmuxPlugins.tokyo-night-tmux;
				extraConfig = ''
					set -g @tokyo-night-tmux_show_git 0             
					set -g @tokyo-night-tmux_show_wbg 0             
					set -g @tokyo-night-tmux_show_netspeed 0        
					set -g @tokyo-night-tmux_show_battery_widget 0  
					set -g @tokyo-night-tmux_show_music 0           
					set -g @tokyo-night-tmux_show_path 0            
					set -g @tokyo-night-tmux_show_hostname 0        
				'';
			}
			{
  				plugin = pkgs.tmuxPlugins.logging;
  				extraConfig = "set -g @logging-path $HOME/Documents";
			}
			{
				# Не в nixpkgs - обёрнут вручную через mkTmuxPlugin.
				# rtpFilePath задан явно: по умолчанию mkTmuxPlugin ищет
				# файл с подчёркиванием (fzf_links.tmux) из pluginName,
				# а у этого плагина точка входа с дефисом (fzf-links.tmux).
				plugin = pkgs.tmuxPlugins.mkTmuxPlugin {
					pluginName = "fzf-links";
					version = "1.4.16";
					rtpFilePath = "fzf-links.tmux";
					src = pkgs.fetchFromGitHub {
						owner = "alberti42";
						repo = "tmux-fzf-links";
						rev = "dc5c0d3fea91bde5c33315f68b0d00ea759e0565"; # tag 1.4.16
						hash = "sha256-KzqdB5JmWFUI95iwlB91KH/zrFNhB4RP6DAi4By6KUE=";
					};
				};
				# По умолчанию биндится на <prefix> C-h - открывает fzf с
				# найденными в панели ссылками/путями/git-адресами.
				extraConfig = ''
					set -g @fzf-links-editor-open-cmd "tmux new-window -n 'nvim' nvim +%line '%file'"
				'';
			}
		];
	};
}
