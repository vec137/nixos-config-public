{ pkgs, ... }:
let
	# Те же настройки VPS, что читает modules/nixos/vpn/base.nix (IP, порты) —
	# чтобы алиас не держал свою копию адресов.
	vpn = import ../nixos/vpn/settings.nix;
in {
	programs.fish = {
		enable = true;
		shellAliases = {
			cat = "bat --style=plain --color=always";
			v = "nvim";
			ls = "eza --icons always";
			ll = "eza -lg --icons always";
			l = "eza -lg --icons always";
			la = "eza -lAg --icons always";
			# --sudo (not --elevate=sudo): nixos-26.05's nixos-rebuild-ng predates
			# the --elevate flag, which only landed in nixos-rebuild-ng after the
			# 26.05 branch point. --sudo is the equivalent for this version --
			# prefixes activation commands with `sudo`, which doas-sudo-shim
			# (see modules/nixos/common.nix) transparently routes to `doas`.
			rebuild-boot = "nixos-rebuild boot --flake /home/nix/.nix#laptop --sudo";
			rebuild-switch = "nixos-rebuild switch --flake /home/nix/.nix#laptop --sudo";
			rebuild-dry-activate = "nixos-rebuild dry-activate --flake /home/nix/.nix#laptop --sudo";

			# The firefox-devtools MCP server attaches to a *running* browser
			# over Marionette (--connect-existing, see browser-mcp.nix), so the
			# mcp profile has to be started with the automation channels open:
			# --marionette is the WebDriver control port (2828, the one the MCP
			# server dials), --remote-debugging-port is the BiDi websocket it
			# needs alongside it. Both are startup-only -- a browser already
			# running without them has to be restarted (session restore brings
			# the tabs back). Plain `librewolf` keeps opening my-profile.
			librewolf-mcp = "librewolf -P mcp --marionette --remote-debugging-port 9222";

			# Shared coursework dev shells (see devShells in flake.nix) -
			# usable from any directory, no per-assignment flake needed.
			dev-py = "nix develop /home/nix/.nix#python";
			dev-java = "nix develop /home/nix/.nix#java";
			dev-cpp = "nix develop /home/nix/.nix#cpp";
		};
		shellInit = '' 
				set fish_escape_delay_ms 1000;
				bind \b 'backward-kill-word'; 
				bind \e\[3\;5~ 'kill-word';
				bind \e\e 'fish_commandline_prepend doas';
			'';
				# if command -v wal > /dev/null 2>&1 && [ "$TERM" = "alacritty" ]
				# 	wal -Rqe
				# end
		functions = {
			fish_greeting = {
				body = '''';
				onEvent = "fish_greeting";
			};
			# HTTPS_PROXY is deliberately not a global sessionVariable (see
			# common.nix) - it used to leak into every app, including
			# cassette, which was routing Yandex Music API calls through the
			# xray tunnel and flapping whenever it hiccuped. Scoped to just
			# this command instead. `command claude` (not `claude`) skips
			# this same function to avoid infinite recursion. Fish autoloads
			# functions for non-interactive invocations too, so this still
			# fires from the tmux/niri autostart path (niri-autostart.sh),
			# not just an interactive shell. 6080 is the mihomo balancer
			# (modules/nixos/mihomo.nix) over Throne and xray.
			claude = {
				body = ''
					set -lx HTTPS_PROXY http://127.0.0.1:6080
					command claude $argv
				'';
			};
			# Routes VMware Workstation Pro's connection to the lab vCenter
			# through the openconnect VPN without a system-wide tun/routing
			# change. Unlike a browser, Workstation Pro has no proxy setting
			# of its own (its vCenter/console traffic isn't HTTP-proxy-aware),
			# so proxychains-ng (from modules/home/profiles/security-tools.nix)
			# is used instead: it's an LD_PRELOAD shim that intercepts this
			# process's connect() calls and tunnels them through the SOCKS5
			# proxy that `ocproxy` exposes on 127.0.0.1:5080 for the same VPN
			# session. See hosts/laptop/default.nix's
			# environment.etc."proxychains-vmware.conf" for the proxy list —
			# kept separate from the shared /etc/proxychains.conf so this
			# never mixes with the pentest-profile proxies (balancer on 6080).
			# `command vmware` (not `vmware`) avoids recursing into this same
			# function, same as the `claude` one above. Requires `ocproxy`
			# already running and pointed at port 5080 before launching.
			vmware = {
				body = ''
					proxychains4 -f /etc/proxychains-vmware.conf vmware $argv
				'';
			};
			# Выкатка VPS из флейка: вычисление здесь, сборка на домашнем
			# сервере (он подписывает результат, VPS принимают только
			# подписанное), копирование `nix copy server → VPS` (через этот
			# ноутбук, но с --use-substitutes VPS сам тянет из cache.nixos.org
			# всё, что там есть, — через ноутбук идёт только своё), активация
			# через sudo на VPS (пароль nix из secrets/vps.yaml спросит один
			# раз на хост). Хосты — из ssh-конфига (modules/home/misc.nix).
			#   deploy-vps ru-edge | nl-exit | all   [доп. флаги nixos-rebuild]
			# Первая установка — не этим, а nixos-anywhere (см.
			# ~/Stuff/xray-bypass/CLAUDE.md).
			deploy-vps = {
				body = ''
					set -l hosts $argv[1]
					set -e argv[1]
					test "$hosts" = all; and set hosts ru-edge nl-exit
					if test -z "$hosts"
						echo "usage: deploy-vps ru-edge|nl-exit|all [nixos-rebuild flags]" >&2
						return 1
					end
					for h in $hosts
						echo "==> $h"
						nixos-rebuild switch --flake ~/.nix#$h \
							--build-host server --target-host $h \
							--use-substitutes --sudo --ask-sudo-password $argv
						or return 1
					end
				'';
			};
			# Break-glass-разблокировка LUKS: SSH прямо в initrd (порт
			# vpn.initrdSshPort) и ручной ввод фразы, когда Clevis/Tang не
			# сработали (дом/Tang недоступны, JWE не тот, Tang-релей лежит):
			#   vps-unlock ru-edge | vps-unlock nl-exit | vps-unlock <host> shell
			# По умолчанию сразу запускается systemd-tty-ask-password-agent (он
			# печатает ожидающие запросы и ждёт фразу); `shell` даёт оболочку, если
			# надо сначала посмотреть journalctl / cryptsetup.
			# Хост-ключ initrd — отдельный от stage-2 хост-ключа (тот же адрес,
			# ДРУГОЙ ключ → в общем known_hosts был бы CONFLICT), поэтому свой
			# known_hosts-файл + accept-new: первый вход пинит ключ, дальше подмена
			# ключа уже ругается. Ключ входа — тот же deploy-ключ (он же в
			# boot.initrd.network.ssh.authorizedKeys = vpn.deployKeys), имя держать
			# в синхроне с modules/home/misc.nix.
			# До nl-exit из дома напрямую не достучаться (провайдер режет ответы с
			# его IP) — идём через mihomo-СОКС на 6080. НО: в сценарии «nl-exit не
			# разблокировался» его обратный туннель лежит, и путь через nl-exit
			# мёртв — группа proxy должна стоять на ДРУГОЙ ноде подписки.
			vps-unlock = {
				body = ''
					set -l host $argv[1]
					# set -l внутри case/switch скоупится к блоку (fish 4.x) —
					# переменную объявляем до switch, внутри только пишем.
					set -l ip
					switch $host
						case ru-edge
							set ip ${vpn.hosts.ru-edge}
						case nl-exit
							set ip ${vpn.hosts.nl-exit}
						case '*'
							echo "usage: vps-unlock ru-edge|nl-exit [shell]" >&2
							return 1
					end
					set -l proxy
					if test $host = nl-exit
						set proxy -o "ProxyCommand=nc -X 5 -x 127.0.0.1:6080 %h %p"
					end
					set -l cmd ssh -t -p ${toString vpn.initrdSshPort} -o ConnectTimeout=15 \
						-o IdentityFile=~/.nix/ssh/vps_deploy_202610 -o IdentitiesOnly=yes \
						-o UserKnownHostsFile=~/.nix/ssh/known_hosts_initrd \
						-o StrictHostKeyChecking=accept-new $proxy root@$ip
					echo "root@$ip:${toString vpn.initrdSshPort} (initrd, stage-1)"
					if test "$argv[2]" = shell
						exec $cmd
					end
					exec $cmd systemd-tty-ask-password-agent
				'';
			};
		};
		plugins = [
			{
				name = "tide";
				src = pkgs.fishPlugins.tide.src;
			}
			{
				name = "grc";
				src = pkgs.fishPlugins.grc.src;
			}
		];
	};
}
