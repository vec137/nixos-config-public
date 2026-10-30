{ pkgs, ... }: {
	# Not imported by default (hosts/laptop/home.nix) — Niri is the WM in
	# daily use. To re-enable: uncomment this file's import there and flip
	# programs.hyprland.enable = true in hosts/laptop/default.nix.
	wayland.windowManager.hyprland = {
		enable = true;
		configType = "hyprlang";
		package = pkgs.hyprland;
		settings = {
			xwayland.enable = true;
			"$mod" = "SUPER";
			exec-once = [
				"xray run -c=/home/nix/.nix/xray/xhttp_reality.json"
				"ciadpi -s1 -q1 -Y -Ar -s5 -o1+s -At -f-1 -r1+s -As -s1 -o1+s -s-1 -An"
				"ayugram-desktop -startintray"
				"iio-hyprland"
				"noctalia-shell"
			];
			monitor = [
				"eDP-1,preferred,auto,1.5"
				"HDMI-A-2,preferred,auto,1.2"
			];
			cursor.inactive_timeout = 3;
			misc = {
				disable_hyprland_logo = true;
				enable_anr_dialog = false;
			};
			ecosystem.no_update_news = true;
			xwayland.force_zero_scaling = true;
			input = {
				kb_layout = "us,ru";
				kb_options = "grp:win_space_toggle";
				sensitivity = -0.5;
				follow_mouse = 1;
				touchpad = {
					natural_scroll = "yes";
				};
			};
			device = {
				name = "synps/2-synaptics-touchpad";
				sensitivity = 0;
			};
			dwindle = {
				pseudotile = "yes";
				preserve_split = "yes";
			};
			decoration = {
				rounding = 15;
				blur = {
					enabled = true;
					xray = true;
					size = 4;
					passes = 4;
					new_optimizations = true;
				};
			};
			animations = {
				enabled = "yes";
				bezier = "quart, 0.25, 1, 0.5, 1";
				animation = [
					"windows, 1, 6, quart, slide"
					"border, 1, 6, quart"
					"borderangle, 1, 6, quart"
					"fade, 1, 6, quart"
					"workspaces, 1, 6, quart"
				];
			};
			windowrule = [
				"float,class:^(org.pulseaudio.pavucontrol)$"
				"pin,class:^(org.pulseaudio.pavucontrol)$"
				"size 900 500,class:^(org.pulseaudio.pavucontrol)$"
				"float,class:^(zenity)$"
				"pin,class:^(zenity)$"
				"float, class:com.ayugram.desktop"
				"center, class:com.ayugram.desktop"
				"size 900 500, class:com.ayugram.desktop"
				"float, class:Discord"
				"center, class:Discord"
				"size 900 500, class:Discord"
				"float, class:org.gnome.Calculator"
				"size 334 493, class:org.gnome.Calculator"
				"center, class:org.gnome.Calculator"
				"opacity 0.0 override 0.0 override,class:^(xwaylandvideobridge)$"
				"noanim,class:^(xwaylandvideobridge)$"
				"noinitialfocus,class:^(xwaylandvideobridge)$"
				"maxsize 1 1,class:^(xwaylandvideobridge)$"
				"noblur,class:^(xwaylandvideobridge)$"
			];
			bindm = [
				"$mod, mouse:272, movewindow"
				"$mod, mouse:273, resizewindow"
			];
			bind = [
				# wm binds
				"$mod, H, movefocus, l"
				"$mod, L, movefocus, r"
				"$mod, K, movefocus, u"
				"$mod, J, movefocus, d"
				"$mod SHIFT, H, movewindow, l"
				"$mod SHIFT, L, movewindow, r"
				"$mod SHIFT, K, movewindow, u"
				"$mod SHIFT, J, movewindow, d"
				"$mod Control_L, H, resizeactive, -15 0"
				"$mod Control_L, L, resizeactive, 15 0"
				"$mod Control_L, J, resizeactive, 0 -15"
				"$mod Control_L, K, resizeactive, 15 0"
				"$mod, 1, workspace, 1"
				"$mod, 2, workspace, 2"
				"$mod, 3, workspace, 3"
				"$mod, 4, workspace, 4"
				"$mod, 5, workspace, 5"
				"$mod, 6, workspace, 6"
				"$mod, 7, workspace, 7"
				"$mod, 8, workspace, 8"
				"$mod, 9, workspace, 9"
				"$mod, 0, workspace, 10"
				"$mod SHIFT, 1, movetoworkspace, 1"
				"$mod SHIFT, 2, movetoworkspace, 2"
				"$mod SHIFT, 3, movetoworkspace, 3"
				"$mod SHIFT, 4, movetoworkspace, 4"
				"$mod SHIFT, 5, movetoworkspace, 5"
				"$mod SHIFT, 6, movetoworkspace, 6"
				"$mod SHIFT, 7, movetoworkspace, 7"
				"$mod SHIFT, 8, movetoworkspace, 8"
				"$mod SHIFT, 9, movetoworkspace, 9"
				"$mod SHIFT, 0, movetoworkspace, 10"
				"$mod, mouse_down, workspace, e+1"
				"$mod, mouse_up, workspace, e-1"
				"$mod, Y, killactive"
				"$mod, V, togglefloating"
				"$mod, T, togglesplit"
				"$mod, G, centerwindow"
				", F11, fullscreen, 0"
				"$mod, R, exec, hyprctl reload"

				# noctalia
				
				"$mod, O, exec, noctalia-shell ipc call controlCenter toggle"
				"$mod, M, exec, noctalia-shell ipc call sessionMenu toggle"
				"$mod, P, exec, noctalia-shell ipc call launcher toggle"
				"ALT SHIFT, D, exec, noctalia-shell ipc call notifications toggleDND"
				"ALT SHIFT, L, exec, noctalia-shell ipc call lockScreen lock"
				"ALT SHIFT, H, exec, noctalia-shell ipc call launcher clipboard"
				"ALT SHIFT, E, exec, noctalia-shell ipc call launcher emoji"

				# programs

				"$mod, RETURN, exec, alacritty"
				"$mod, E, exec, nautilus"
				"$mod, S, exec, grimblast --notify --freeze copysave output"
				", PRINT, exec, grimblast --notify --freeze copysave output"
				"$mod SHIFT, S, exec, grimblast --notify --freeze copysave area"
				"SHIFT, PRINT, exec, grimblast --notify --freeze copysave screen"
				"ALT SHIFT, C, exec, gnome-calculator"

				# media

				",XF86AudioRaiseVolume, exec, noctalia-shell ipc call volume increase"
				",XF86AudioLowerVolume, exec, noctalia-shell ipc call volume decrease"
				",XF86AudioMute, exec, noctalia-shell ipc call volume muteOutput"
				"ALT SHIFT, F4, exec, noctalia-shell ipc call volume muteOutput"
				",XF86AudioPlay, exec, noctalia-shell ipc call media playPause"
				",XF86AudioNext, exec, noctalia-shell ipc call media next"
				",XF86AudioPrev, exec, noctalia-shell ipc call media previous"
				"ALT SHIFT, F1, exec, noctalia-shell ipc call media playPause"
				"ALT SHIFT, F2, exec, noctalia-shell ipc call media next"
				"ALT SHIFT, F3, exec, noctalia-shell ipc call media previous"
				",XF86MonBrightnessUp, exec, noctalia-shell ipc call brightness increase"
				",XF86MonBrightnessDown, exec, noctalia-shell ipc call brightness decrease"
				"ALT SHIFT, F11, exec, noctalia-shell ipc call brightness increase"
				"ALT SHIFT, F12, exec, noctalia-shell ipc call brightness decrease"
			];
		};
	};
}
