{
	description = "My system config";
	
	inputs = {
		nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

		nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

		nixpkgs-master.url = "github:nixos/nixpkgs/master";
		
		home-manager = {
			url = "github:nix-community/home-manager";
			inputs.nixpkgs.follows = "nixpkgs";
		};
		
		disko = {
			url = "github:nix-community/disko";
			inputs.nixpkgs.follows = "nixpkgs";
		};

		# Готовые образы установщика от nix-community. Нужен только ради
		# nixosModules.kexec-installer — из него собирается свой kexec-тарбол с
		# zram (packages.kexec-zram ниже) для установки на VPS с 1 ГБ RAM.
		# follows: у nixos-images свои nixos-stable/nixos-unstable, подменяем их
		# нашими, чтобы в замыкание не затянуло второй nixpkgs.
		nixos-images = {
			url = "github:nix-community/nixos-images";
			inputs.nixos-stable.follows = "nixpkgs";
			inputs.nixos-unstable.follows = "nixpkgs-unstable";
		};

		nixvim = {
			url = "github:nix-community/nixvim";
			inputs.nixpkgs.follows = "nixpkgs";
		};

		nixos-hardware = {
			url = "github:NixOS/nixos-hardware/master";
		};

		niri.url = "github:epireyn/niri-flake";

		spicetify-fix.url = "github:neonvoidx/nixpkgs/spicetify-cli-fix";

		spicetify-nix.url = "github:Gerg-L/spicetify-nix";

		# nixpkgs.follows deliberately omitted: noctalia's own binary cache
		# (noctalia.cachix.org, see modules/nixos/common.nix) is only usable
		# if its package is built against exactly the nixpkgs revision its
		# own CI uses. Following our pinned nixpkgs (nixos-26.05) produces a
		# different input hash than upstream ever pushed, forcing a full
		# local C++ compile every time instead of a cache hit. Same reason
		# niri/spicetify-nix/spicetify-fix below don't follow either.
		noctalia = {
			url = "github:noctalia-dev/noctalia-shell";
		};

		burp = {
      		inputs.nixpkgs.follows = "nixpkgs";
      		url = "github:xiv3r/Burpsuite-Professional";
    	};

		stylix = {
      		url = "github:nix-community/stylix";
      		inputs.nixpkgs.follows = "nixpkgs";
    	};

		hermes = {
			url = "github:nousresearch/hermes-agent";
			inputs.nixpkgs.follows = "nixpkgs";
		};

		sops-nix = {
			url = "github:Mic92/sops-nix";
			inputs.nixpkgs.follows = "nixpkgs";
		};

		# Способ выката VPS (deploy.nodes ниже); прежний deploy-vps
		# (modules/home/fish.nix) не используется. Даёт magic rollback: nixos-rebuild switch
		# применяет новый конфиг немедленно и без подстраховки, если он сам
		# разрывает доступ (сломанный nftables/sshd) — safety-разбор в Step 8
		# install-vps.md защищает только ребут (грузчик ставится до
		# активации), а не саму активацию. deploy-rs после переключения сам
		# стучится по ssh обратно и откатывает профиль, если за 30с не
		# дозвонился.
		deploy-rs = {
			url = "github:serokell/deploy-rs";
			inputs.nixpkgs.follows = "nixpkgs";
		};
	};

	outputs = { self, nixpkgs, disko, home-manager, nixos-hardware, ...}@inputs:
		let
			system = "x86_64-linux";
			pkgs = nixpkgs.legacyPackages.${system};
    		# Base nixpkgs is the stable release branch (see the `nixpkgs` input) for
    		# a smaller, better-tested closure. `pkgs-unstable`/`pkgs-master` give
    		# any module an escape hatch to a rolling or bleeding-edge package set
    		# for the specific packages that need to stay fresh (e.g. security-tools
    		# pulling pentest tooling from pkgs-unstable) without moving the whole
    		# system off stable.
    		overlay-bleeding = final: prev: {
    			pkgs-unstable = import inputs.nixpkgs-unstable {
    				inherit system;
    				config.allowUnfree = true;
    			};
    			pkgs-master = import inputs.nixpkgs-master {
    				inherit system;
    				config.allowUnfree = true;
    			};
    		};
    		
    		# Локальные пакеты поверх nixpkgs. Пока их два:
    		# filebrowser-quantum в nixpkgs — 1.5.2-stable, в котором сломано
    		# скачивание публичных шар (HTTP 500 на любую) и нет двух более поздних
    		# правок безопасности, одна из них — утечка содержимого файлов анонимным
    		# посетителям шары. Разбор и обоснование версии —
    		# в pkgs/filebrowser-quantum.nix.
    		overlay-local = final: prev: {
    			# Прекомпилированные релизные бинарники апстрима (из исходников
    			# здесь собиралось бы ~30 минут Rust-пространства) — см. pkgs/wordcraft.nix.
    			wordcraft = final.callPackage ./pkgs/wordcraft.nix { };
    			filebrowser-quantum = final.callPackage ./pkgs/filebrowser-quantum.nix {
    				# 1.5.8 требует Go >= 1.27 (backend/go.mod). go_1_27 есть в стабильном
    				# nixpkgs, поэтому в unstable лезть не нужно.
    				buildGoModule = prev.buildGoModule.override { go = prev.go_1_27; };
    			};
    		};

    		# Shared scaffolding for every host: overlays, disko and the
    		# home-manager NixOS module wiring. Host-specific bits (disk layout,
    		# hardware modules, the host's own config, its home-manager entry)
    		# are passed in as extraModules by each nixosConfigurations.<name>.
    		#
    		# stylix's NixOS module is deliberately NOT imported here: it's unused
    		# (modules/home/stylix.nix is commented out of hosts/laptop/home.nix,
    		# no stylix.enable anywhere) and its regreet submodule references a
    		# services.displayManager option that nixpkgs renamed/removed after
    		# the nixos-26.05 branch point, so importing it unconditionally just
    		# breaks eval on stable for no benefit. The `stylix` flake input is
    		# kept so re-enabling it later is a one-line change, not a re-add.
    		mkHost = name: extraModules: nixpkgs.lib.nixosSystem {
    			inherit system;
    			specialArgs.inputs = inputs;
    			modules = [
    				{
    					nixpkgs.overlays = [
    						overlay-bleeding
    						overlay-local
    						inputs.niri.overlays.niri
    					];
    				}
    				./modules/nixos/common.nix
    				disko.nixosModules.disko
    				inputs.sops-nix.nixosModules.sops
    				home-manager.nixosModules.home-manager
    				{
    					home-manager.useGlobalPkgs = true;
    					home-manager.useUserPackages = true;
    					home-manager.extraSpecialArgs = {
    							inherit inputs;
    							};
    					home-manager.backupFileExtension = "bk";
    					home-manager.backupCommand = "${pkgs.trash-cli}/bin/trash";
    				}
    			] ++ extraModules;
    		};

    		# VPS: без home-manager, desktop-оверлеев и modules/nixos/common.nix —
    		# всё общее для них в modules/nixos/vpn/base.nix. Собираются на
    		# домашнем сервере и выкатываются с ноутбука, см. deploy.nodes ниже
    		# и ~/Stuff/xray-bypass/CLAUDE.md.
    		mkVps = name: nixpkgs.lib.nixosSystem {
    			inherit system;
    			specialArgs.inputs = inputs;
    			modules = [
    				# Только overlay-local: он правит версию пакета (см. ниже), а не
    				# тянет desktop-окружение. overlay-bleeding сюда намеренно не идёт —
    				# pkgs-unstable/pkgs-master на VPS не нужны.
    				{ nixpkgs.overlays = [ overlay-local ]; }
    				disko.nixosModules.disko
    				inputs.sops-nix.nixosModules.sops
    				./hosts/${name}/default.nix
    			];
    		};
		in {
			nixosConfigurations.laptop = mkHost "laptop" [
				./hosts/laptop/disk-config.nix
				{
					_module.args.disks = [ "/dev/nvme0n1" ];
				}
				./hosts/laptop/default.nix
				{
					home-manager.users.nix = import ./hosts/laptop/home.nix;
				}
			];

			# Headless host: EPYC 7402 / RTX 4070, dual-boots with Windows
			# (Windows owns its own SSD and its own ESP; nothing here touches
			# that disk -- see hosts/server/disk-config.nix for why the other
			# two drives are deliberately absent from disko).
			#
			# Runs the VirtualBox-based coursework pipeline and local llama.cpp
			# inference, driven entirely over SSH -- no GUI session is ever
			# started, which is why hosts/server/home.nix imports only
			# modules/home/common.nix and not desktop.nix.
			nixosConfigurations.server = mkHost "server" [
				./hosts/server/disk-config.nix
				{
					# Path from /dev/disk/by-id/, not /dev/nvmeXn1: with three
					# drives in the machine, kernel enumeration order is not
					# stable across boots, and disko unconditionally wipes
					# whatever this resolves to. Fill in before installing:
					#   ls -l /dev/disk/by-id/ | grep -v part
					_module.args.disks = [ "/dev/disk/by-id/nvme-KINGSTON_SNV2S1000G_50026B728366A2D1" ];
				}
				./hosts/server/default.nix
				{
					home-manager.users.nix = import ./hosts/server/home.nix;
				}
			];

			# Временный второй сервер: платформа (мать + CPU + RAM) от старого ПК
			# на втором комплекте разъёмов блока питания основного сервера. Под
			# тяжёлые агентские задачи — агент поднимает здесь виртуалки и
			# работает в них (libvirt/KVM + VirtualBox + VMware Workstation,
			# см. hosts/forge/default.nix). Инференс остаётся на `server`.
			#
			# ПЕРЕД установкой: заполнить диск ниже и hosts/forge/
			# hardware-configuration.nix, порядок шагов — docs/install-forge.md.
			nixosConfigurations.forge = mkHost "forge" [
				./hosts/forge/disk-config.nix
				{
					# ЗАПОЛНИТЬ: путь из /dev/disk/by-id/, не /dev/sda — disko
					# безусловно затирает то, во что это разрешится.
					#   ls -l /dev/disk/by-id/ | grep -v part
					_module.args.disks = [ "/dev/disk/by-id/ata-TOSHIBA_HDWD110_911J5U1FS" ];
				}
				./hosts/forge/default.nix
				{
					home-manager.users.nix = import ./hosts/forge/home.nix;
				}
			];

			nixosConfigurations.ru-edge = mkVps "ru-edge";
			nixosConfigurations.nl-exit = mkVps "nl-exit";

			# deploy-rs (вход выше). hostname — голый алиас из ~/.ssh/config
			# (modules/home/misc.nix): там же порт, identityFile и ProxyJump
			# nl-exit → ru-edge, deploy-rs просто зовёт системный ssh и
			# наследует их как есть. sshUser отдельно от user: по ssh входим
			# как nix (vps_deploy), активируем как root — VPS требует пароль
			# sudo (security.sudo.wheelNeedsPassword в modules/nixos/vpn/
			# base.nix), interactiveSudo его спросит, как раньше делал
			# --ask-sudo-password. fast_connection не задан — значит
			# deploy-rs передаёт `nix copy` флаг --substitute-on-destination
			# по умолчанию, это и есть аналог --use-substitutes: VPS сам
			# тянет из cache.nixos.org всё, что там есть, через ноутбук идёт
			# только то, что собрано на server и подписано его ключом
			# (serverSigningKey в vpn/settings.nix, VPS ему доверяет).
			deploy.nodes.ru-edge = {
				hostname = "ru-edge";
				sshUser = "nix";
				profiles.system = {
					user = "root";
					interactiveSudo = true;
					path = inputs.deploy-rs.lib.${system}.activate.nixos
						self.nixosConfigurations.ru-edge;
				};
			};
			deploy.nodes.nl-exit = {
				hostname = "nl-exit";
				sshUser = "nix";
				profiles.system = {
					user = "root";
					interactiveSudo = true;
					path = inputs.deploy-rs.lib.${system}.activate.nixos
						self.nixosConfigurations.nl-exit;
				};
			};

			checks.${system} = inputs.deploy-rs.lib.${system}.deployChecks self.deploy;

			# Собственный установочный образ под эту машину — см.
			# hosts/installer/default.nix. Собирается НЕ через mkHost: тому
			# нужны disko, sops-nix, home-manager и modules/nixos/common.nix с
			# sops.age.sshKeyPaths, а установочной среде всё это только мешает
			# (ключей хоста там ещё нет, расшифровывать нечего и нечем).
			#
			#   nix build .#installer-iso --print-out-paths
			nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
				inherit system;
				specialArgs.inputs = inputs;
				modules = [ ./hosts/installer/default.nix ];
			};


			# Самодостаточный установочный образ ДЛЯ forge — отдельно от
			# installer выше. Тот образ рассчитан на установку, в которой
			# участвует ноутбук (ssh, сборка по сети); до forge доступа по ssh
			# не предполагается, поэтому здесь в образ вшивается ГОТОВОЕ
			# замыкание системы forge и скрипт install-forge: загрузился с
			# флешки, ввёл одну команду, получил установленную систему. Сеть
			# при установке не нужна вообще.
			#
			# Три аргумента через specialArgs (а не импортом внутри модуля):
			# рекурсии нет — forge про установщик ничего не знает, ссылка
			# только в одну сторону.
			#   forgeSystem      — замыкание системы, его ставит nixos-install --system;
			#   forgeDiskoScript — сгенерированный disko-скрипт; установщик
			#                      подменяет в нём литерал диска на $DISK,
			#                      чтобы цель выбиралась в момент установки;
			#   repoSource       — исходники флейка, копия ложится в /home/nix/.nix.
			#
			#   nix build .#forge-installer-iso --print-out-paths
			#
			# ВАЖНО: образ содержит систему целиком, то есть после каждой
			# правки hosts/forge/* его надо пересобирать.
			nixosConfigurations.forge-installer = nixpkgs.lib.nixosSystem {
				inherit system;
				specialArgs = {
					inherit inputs;
					forgeSystem = self.nixosConfigurations.forge.config.system.build.toplevel;
					forgeDiskoScript = self.nixosConfigurations.forge.config.system.build.diskoScript;
					repoSource = self;
				};
				modules = [ ./hosts/installer-forge/default.nix ];
			};

			# Свой kexec-образ установщика С ZRAM — для VPS, где штатный kexec
			# nixos-anywhere падает по OOM (у ru-edge 1 ГБ RAM).
			#
			# Почему это лечит OOM: после kexec установщик распаковывает весь свой
			# /nix/store в tmpfs, то есть целиком в RAM, и на 1 ГБ не укладывается.
			# Страницы tmpfs свопируемые, поэтому zram (сжатие zstd, ~3x) даёт
			# установщику пережить распаковку. В штатном образе nixos-images zram
			# НЕ включён, своего флага у nixos-anywhere пока нет (PR #652 открыт),
			# поэтому собираем образ сами и подаём его через --kexec.
			#
			#   nix build ~/.nix#kexec-zram --print-out-paths
			#   nixos-anywhere ... --kexec <путь>/nixos-kexec-installer-*.tar.gz
			nixosConfigurations.kexec-zram = nixpkgs.lib.nixosSystem {
				inherit system;
				modules = [
					inputs.nixos-images.nixosModules.kexec-installer
					inputs.nixos-images.nixosModules.noninteractive
					({ lib, pkgs, ... }: {
						zramSwap = {
							enable = true;
							algorithm = "zstd";
							# Больше 100% осмысленно: zram хранит сжатое, так что
							# устройство на 1.5x RAM реально занимает кратно меньше.
							memoryPercent = 150;
						};
						# Выталкивать в zram охотно: он на порядки быстрее диска, а
						# нам важно не умереть по RAM, а не latency.
						boot.kernel.sysctl = {
							"vm.swappiness" = 180;
							"vm.page-cluster" = 0;
						};

						# Ужать initrd. Он грузится в физическую RAM ЦЕЛИКОМ и эти
						# страницы не свопятся, поэтому на 1 ГБ его размер — главный
						# лимит: если места не находится, kexec_load(2) отвечает
						# «Invalid argument». Нам нужны только ext4 (корень) и vfat
						# (ESP), всё остальное — чужие драйверы и userland. Выключаем
						# поштучно, чтобы не снести overlay/squashfs/tmpfs, на которых
						# держится сам установщик.
						boot.supportedFilesystems = {
							bcachefs = lib.mkForce false;
							btrfs = lib.mkForce false;
							f2fs = lib.mkForce false;
							ntfs = lib.mkForce false;
							xfs = lib.mkForce false;
							zfs = lib.mkForce false;
						};

						# Набор инструментов разметки задаём сами: с --no-disko-deps
						# disko берёт их из самого установщика. cryptsetup в штатном
						# образе отсутствует — без него фаза разметки упала бы на
						# создании LUKS; zfs-user, наоборот, не нужен (ZFS выключен).
						environment.defaultPackages = lib.mkOverride 10 (with pkgs; [
							parted
							gptfdisk
							e2fsprogs
							dosfstools
							cryptsetup
						]);

						# nixos-rebuild установщику не нужен (ставим через
						# nixos-install), а тянет он за собой python3 — 127 МБ в
						# замыкании, то есть прямой вклад в размер initrd.
						system.tools.nixos-rebuild.enable = false;
					})
				];
			};

			# Артефакты-установщики отдельными выходами, чтобы не выписывать каждый
			# раз длинные пути config.system.build.*. Один attrset, а не два
			# packages.${system}.<имя> — иначе Nix ругается на повторное
			# определение динамического атрибута.
			packages.${system} = {
				# Пакет из overlay-local отдельным выходом, чтобы собрать его
				# можно было командой `nix build .#wordcraft`, не трогая toplevel.
				wordcraft = (import nixpkgs {
					inherit system;
					overlays = [ overlay-local ];
				}).wordcraft;
				installer-iso =
					self.nixosConfigurations.installer.config.system.build.isoImage;
				forge-installer-iso =
					self.nixosConfigurations.forge-installer.config.system.build.isoImage;
				kexec-zram =
					self.nixosConfigurations.kexec-zram.config.system.build.kexecInstallerTarball;
			};

			# General-purpose per-language dev shells for coursework, so a new
			# shell.nix/flake.nix doesn't need writing for every assignment -
			# `nix develop ~/.nix#python` (or the dev-py/dev-java/dev-cpp fish
			# aliases, see modules/home/fish.nix) from any project directory.
			# Modeled after the ad-hoc flakes/shell.nix files already used for
			# past coursework under ~/Stuff/sut (mkShell + `shellHook = fish`
			# to hand control back to fish, since nix develop otherwise drops
			# into bash).
			devShells.${system} = {
				python = pkgs.mkShell {
					packages = [
						(pkgs.python3.withPackages (p: with p; [
							numpy
							pandas
							matplotlib
							requests
						]))
					];
					shellHook = ''
						fish
					'';
				};
				java = pkgs.mkShell {
					packages = [ pkgs.jdk ];
					shellHook = ''
						fish
					'';
				};
				cpp = pkgs.mkShell {
					packages = with pkgs; [ gcc clang clang-tools cmake gdb bear ];
					shellHook = ''
						fish
					'';
				};
			};
		};
}
