{ pkgs, lib, ... }: {
	programs.niri = {
		enable = true;
		package = pkgs.niri-unstable;
		settings = {
			outputs = {
				"eDP-1".scale = 1.5;
				"HDMI-A-2".scale = 1.2;
			};
			# Статическое объявление обязательно: window-rule'ы ниже ссылаются
			# на эти имена через open-on-workspace, а по документации niri
			# "if such a workspace does not exist, the window will open on
			# the currently focused workspace as usual" - то есть без
			# статического объявления niri НЕ создаёт именованный workspace
			# по требованию, а просто игнорирует open-on-workspace и роняет
			# окно на текущий активный стол. Раньше этот блок был удалён в
			# попытке избавиться от вечно пустых рабочих столов в overview
			# (статически объявленные workspace'ы действительно существуют
			# всегда, даже без окон) - но это сломало реальную маршрутизацию:
			# virt-manager/moonlight стали открываться на 1-main вместе с
			# librewolf вместо своих 2-vms/3-gaming. Корректность раскладки
			# важнее эстетики overview, так что блок возвращён.
			workspaces = {
				"laptop-media" = {
					open-on-output = "eDP-1";
				};
				"1-main" = {
					open-on-output = "HDMI-A-2";
				};
				"2-vms" = {
					open-on-output = "HDMI-A-2";
				};
				"3-gaming" = {
					open-on-output = "HDMI-A-2";
				};
			};
			input = {
				focus-follows-mouse.enable = true;
				warp-mouse-to-focus.enable = true;
				keyboard.xkb = {
					layout = "us,ru";
					options = "grp:win_space_toggle";
				};
				mouse.accel-speed = -0.5;
				tablet.map-to-output = "eDP-1";
				touch.map-to-output = "eDP-1";
			};
			cursor.hide-after-inactive-ms = 3000;
			hotkey-overlay.skip-at-startup = true;
			prefer-no-csd = true;
			screenshot-path = "~/Pictures/%Y%m%d_%H%M%S.png";
			xwayland-satellite = {
				enable = true;
				path = lib.getExe pkgs.xwayland-satellite-unstable;
			};
			debug.honor-xdg-activation-with-invalid-serial = [];
			spawn-at-startup = [
				# Разрешает root-процессам (doas/su) подключаться к X-дисплею этой
				# сессии через xwayland-satellite. Без этого GUI-приложения,
				# запущенные через "doas <app>" (например vmware-netcfg), падают
				# с "Authorization required" - тут нет ~/.Xauthority вообще ни у
				# кого, доступ проверяется по UID подключающегося процесса, а не
				# по cookie, и root в этот список по умолчанию не входит.
				# Компромисс: любой root-процесс на этой машине получает доступ
				# к дисплею на всё время сессии, не только целевое приложение.
				{ argv = [ "${pkgs.xhost}/bin/xhost" "+si:localuser:root" ]; }
				{ argv = [ "noctalia" ]; }
				# xray запускается системным юнитом xray@ (hosts/laptop/default.nix).
				{ argv = [ "ciadpi" "-s1" "-q1" "-Y" "-Ar" "-s5" "-o1+s" "-At" "-f-1" "-r1+s" "-As" "-s1" "-o1+s" "-s-1" "-An" ]; }
				{ argv = [ "AyuGram" "-startintray" ]; }
				{ argv = [ "iio-niri" "listen" "--monitor" "eDP-1" ]; }

				# Автозапуск и организация окон через внешний скрипт
				{ argv = [ "${./scripts/niri-autostart.sh}" ]; }
			];
			window-rules = [
				{
					matches = [
						{ app-id = "org.pulseaudio.pavucontrol"; } 
						{ app-id = "com.ayugram.desktop"; }
						{ app-id = "Discord"; }
					];
					open-floating = true;
					default-column-width.fixed = 900;
					default-window-height.fixed = 500;
				}
				{
					matches = [
						{ app-id = "org.gnome.Calculator"; }
					];
					open-floating = true;
					default-column-width.fixed = 334;
					default-window-height.fixed = 493;
				}

				# Окна на ноутбуке (eDP-1)
				{
					matches = [
						{ app-id = "cava"; }
						{ app-id = "cassette"; }
						{ app-id = "Cassette"; }
						{ app-id = "space.rirusha.Cassette"; }
						{ app-id = "com.github.cassette"; }
						{ app-id = "com.vlink.Cassette"; }
						{ app-id = "Spotify"; }
						{ app-id = "spotify"; }
					];
					open-on-output = "eDP-1";
					open-on-workspace = "laptop-media";
					open-maximized = true;
				}

				# 1-main: Главный рабочий стол на внешнем мониторе (HDMI-A-2)
				{
					matches = [
						{ app-id = "LibreWolf"; }
						{ app-id = "librewolf"; }
						{ app-id = "obsidian"; }
						{ app-id = "md.Obsidian"; }
						{ app-id = "tmux-dev"; }
					];
					open-on-output = "HDMI-A-2";
					open-on-workspace = "1-main";
					open-maximized = true;
				}

				# 2-vms: Второй рабочий стол на внешнем мониторе
				{
					matches = [
						{ app-id = "virt-manager"; }
						{ app-id = "org.virt-manager.virt-manager"; }
						# Настоящий app-id (подтверждено вживую через niri msg -j
						# windows) - nixpkgs оборачивает бинарник, и GTK берёт
						# app-id из argv[0] обёртки, а не из .desktop-файла.
						{ app-id = ".virt-manager-wrapped"; }
					];
					open-on-output = "HDMI-A-2";
					open-on-workspace = "2-vms";
					open-focused = false;
					open-maximized = true;
				}

				# 3-gaming: Самый нижний рабочий стол на внешнем мониторе
				{
					matches = [
						{ app-id = "com.moonlight_stream.Moonlight"; }
						{ app-id = "moonlight"; }
						{ app-id = "Moonlight"; }
					];
					open-on-output = "HDMI-A-2";
					open-on-workspace = "3-gaming";
					open-focused = false;
					open-maximized = true;
				}
			];
			binds = {
				"Mod+Return".action.spawn = "alacritty";
				"Mod+E".action.spawn = "nautilus";
				"Alt+Shift+C".action.spawn = "gnome-calculator";
				"Print".action.screenshot-screen = {};
				"Shift+Print".action.screenshot = {};
				"Alt+Print".action.screenshot-window = {};
				"Mod+Alt+S".action.screenshot-window = {};
				"Mod+S".action.screenshot-screen = {};
				"Mod+Shift+S".action.screenshot = {};

				"Mod+O".action.spawn = [ "noctalia" "msg" "panel-toggle" "control-center" ];
				"Mod+P".action.spawn = [ "noctalia" "msg" "panel-toggle" "launcher" ];
				"Mod+M".action.spawn = [ "noctalia" "msg" "panel-toggle" "session" ];
				"Mod+Shift+Slash".action.show-hotkey-overlay = {};
				"Alt+Shift+D".action.spawn = [ "noctalia" "msg" "notification-dnd-toggle" ];
				"Alt+Shift+L".action.spawn = [ "noctalia" "msg" "session" "lock" ];
				"Alt+Shift+H".action.spawn = [ "noctalia" "msg" "panel-toggle" "clipboard" ];
				"Alt+Shift+E".action.spawn = [ "noctalia" "msg" "panel-toggle" "launcher" "/emo" ];
				"Alt+Shift+F5".action.spawn = [ "noctalia" "msg" "panel-toggle" "pozzoo/hassio:entity_manager" ];

				"XF86AudioRaiseVolume".action.spawn = [ "noctalia" "msg" "volume-up" "5" ];
				"XF86AudioLowerVolume".action.spawn = [ "noctalia" "msg" "volume-down" "5" ];
				"XF86AudioMute".action.spawn = [ "noctalia" "msg" "volume-mute" ];
				"Alt+Shift+F4".action.spawn = [ "noctalia" "msg" "volume-mute" ];
				"XF86AudioPlay".action.spawn = [ "noctalia" "msg" "media" "toggle" ];
				"XF86AudioPrev".action.spawn = [ "noctalia" "msg" "media" "previous" ];
				"XF86AudioNext".action.spawn = [ "noctalia" "msg" "media" "next" ];
				"Alt+Shift+F1".action.spawn = [ "noctalia" "msg" "media" "toggle" ];
				"Alt+Shift+F2".action.spawn = [ "noctalia" "msg" "media" "next" ];
				"Alt+Shift+F3".action.spawn = [ "noctalia" "msg" "media" "previous" ];
				"XF86MonBrightnessUp".action.spawn = [ "noctalia" "msg" "brightness-up" "eDP-1" "5" ];
				"XF86MonBrightnessDown".action.spawn = [ "noctalia" "msg" "brightness-down" "eDP-1" "5" ];
				"Alt+Shift+F11".action.spawn = [ "noctalia" "msg" "brightness-up" "eDP-1" "5" ];
				"Alt+Shift+F12".action.spawn = [ "noctalia" "msg" "brightness-down" "eDP-1" "5" ];

				"Mod+Y" = {
					action.close-window = {};
					repeat = false;
				};
				"Mod+G" = {
					action.toggle-overview = {};
					repeat = false;
				};
				"Mod+Escape" = {
					allow-inhibiting = false;
					action.toggle-keyboard-shortcuts-inhibit = {};
				};
				"Mod+F".action.maximize-column = {};
				"Mod+Shift+F".action.fullscreen-window = {};
				"Mod+Ctrl+F".action.expand-column-to-available-width = {};
				"F11".action.fullscreen-window = {};
				"Mod+C".action.center-column = {};
				"Mod+V".action.toggle-window-floating = {};
				"Mod+Shift+V".action.switch-focus-between-floating-and-tiling = {};
				"Mod+Shift+Q".action.quit = { skip-confirmation = false; };

				"Mod+H".action.focus-column-left = {};
				"Mod+L".action.focus-column-right = {};
				"Mod+J".action.focus-window-or-workspace-down = {};
				"Mod+K".action.focus-window-or-workspace-up = {};
				"Mod+Ctrl+H".action.focus-monitor-left = {};
				"Mod+Ctrl+L".action.focus-monitor-right = {};

				"Mod+Shift+H".action.move-column-left = {};
				"Mod+Shift+L".action.move-column-right = {};
				"Mod+Shift+J".action.move-window-down-or-to-workspace-down = {};
				"Mod+Shift+K".action.move-window-up-or-to-workspace-up = {};
				"Mod+Ctrl+Shift+H".action.move-column-to-monitor-left = {};
				"Mod+Ctrl+Shift+L".action.move-column-to-monitor-right = {};
				"Mod+WheelScrollDown".action.focus-window-or-workspace-down = {};
				"Mod+WheelScrollUp".action.focus-window-or-workspace-up = {};
				"Mod+BracketLeft".action.consume-or-expel-window-left = {};
				"Mod+BracketRight".action.consume-or-expel-window-right = {};
				"Mod+R".action.switch-preset-column-width = {};
				"Mod+T".action.toggle-column-tabbed-display = {};
				"Mod+Minus".action.set-column-width = "-20%";
				"Mod+Equal".action.set-column-width = "+20%";
				"Mod+Shift+Minus".action.set-column-width = "-10%";
				"Mod+Shift+Equal".action.set-column-width = "+10%";

				"Mod+1".action.focus-workspace = 1;
				"Mod+2".action.focus-workspace = 2;
				"Mod+3".action.focus-workspace = 3;
				"Mod+4".action.focus-workspace = 4;
				"Mod+5".action.focus-workspace = 5;
				"Mod+6".action.focus-workspace = 6;
				"Mod+7".action.focus-workspace = 7;
				"Mod+8".action.focus-workspace = 8;
				"Mod+9".action.focus-workspace = 9;
				"Mod+0".action.focus-workspace = 10;

				"Mod+Shift+1".action.move-column-to-workspace = 1;
				"Mod+Shift+2".action.move-column-to-workspace = 2;
				"Mod+Shift+3".action.move-column-to-workspace = 3;
				"Mod+Shift+4".action.move-column-to-workspace = 4;
				"Mod+Shift+5".action.move-column-to-workspace = 5;
				"Mod+Shift+6".action.move-column-to-workspace = 6;
				"Mod+Shift+7".action.move-column-to-workspace = 7;
				"Mod+Shift+8".action.move-column-to-workspace = 8;
				"Mod+Shift+9".action.move-column-to-workspace = 9;
				"Mod+Shift+0".action.move-column-to-workspace = 10;
			};
		};
	};
}
