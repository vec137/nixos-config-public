{ lib, pkgs, ... }:
{
  # Settings that hold regardless of which machine this is: which caches to
  # trust, base locale, doas instead of sudo, the base user account shape,
  # and unfree/insecure package policy. Hardware- and host-specific things
  # (boot, power management, services tied to this laptop) stay in the
  # host's own default.nix.

  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = pkg:
      let
        name = lib.getName pkg;
      in
      builtins.elem name [
        "discord-canary"
        "unrar"
        "yandex-music"
        "spotify"
        "obsidian"
        "stegsolve"
        "hiddify-core"
        "hiddify-app"
        "teamspeak"
        "teamspeak3"
        "teamspeak6-client"
        "intel-ocl"
        "libfprint-2-tod1-goodix"
        "corefonts"
        "vista-fonts"
        "cisco-packet-tracer"
        "CiscoPacketTracer_900_Ubuntu_64bit.deb"
        "presence.nvim"
      ];
    permittedInsecurePackages = [
      "openssl-1.1.1w"
      "librewolf-151.0.2-1"
      "librewolf-unwrapped-151.0.2-1"
    ];
  };

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      extra-substituters = [
        "https://nix-community.cachix.org"
        "https://niri-epireyn.cachix.org"
        "https://niri.cachix.org"
        "https://noctalia.cachix.org"
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
        "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
        "niri-epireyn.cachix.org-1:tlVyFN7CtsDT+ZcLPS+ekFWeT1X6X4OqvWqbBMyIzFA="
      ];
      # Default trusted-users is just [ "root" ]. `nixos-rebuild`/`nh os
      # switch` build the new generation as the invoking user (nix), only
      # switching to doas/root for the final activation script — so on the
      # laptop, which has nix.buildMachines configured, every such build
      # goes through the daemon's build-hook/remote-dispatch path. That path
      # requires the requester be trusted for any non-content-addressed
      # derivation (nixpkgs default) whenever a build machine could in
      # principle be used — even when it ultimately falls back to building
      # locally — or the daemon refuses outright with "you are not
      # privileged to build input-addressed derivations". Hit this
      # concretely on 2026-09-21 rebuilding after adding the server as a
      # build machine. Harmless on the server, which doesn't set
      # buildMachines.
      trusted-users = [ "root" "nix" ];
    };
  };

  # Скачиванием подстановок занимается nix-daemon — отдельный системный
  # процесс, а не тот `nix`, что запущен в терминале. Поэтому https_proxy
  # из шелла (и LD_PRELOAD от proxychains) до него не доходит: переменные
  # окружения не наследуются через unix-сокет демона. Прокси надо задавать
  # самому юниту.
  #
  # Зачем вообще: 2026-09-24 маршрут до части адресов cachix оборвался —
  # TLS-хендшейк проходит, приходит ~19 КБ, дальше поток глохнет намертво
  # (nix показывает «скорость меньше байта/с» и висит до таймаута). Отказ
  # привязан к конкретным IP, а не к домену: при `--resolve` на 8.6.112.6
  # тот же NAR качается на 16 МБ/с, на 8.47.69.6 и 104.26.x — 0/3. Оба
  # хоста, ноутбук и сервер, ведут себя одинаково; cache.nixos.org и
  # прочие CDN (Fastly, остальной Cloudflare) не затронуты.
  #
  # Пин в networking.hosts был бы проще, но DNS cachix отдаёт разные
  # наборы адресов со временем (видели и 8.x, и 104.26.x для одного
  # домена), так что закреплённый адрес — это отложенная поломка.
  # Через прокси те же NAR идут стабильно, поэтому маршрутизируем только
  # cachix, а cache.nixos.org и локальную сеть оставляем напрямую —
  # незачем гнать гигабайты через туннель.
  #
  # Переменные строчными: curl внутри nix читает именно https_proxy;
  # HTTPS_PROXY в верхнем регистре curl намеренно игнорирует (наследие
  # CGI, где заголовок Proxy: попал бы в окружение как HTTP_PROXY).
  systemd.services.nix-daemon.environment = {
    https_proxy = "http://127.0.0.1:4080";
    http_proxy = "http://127.0.0.1:4080";
    no_proxy = "127.0.0.1,localhost,::1,cache.nixos.org,channels.nixos.org";
  };

  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "lat4a-19";
    useXkbConfig = true; # use xkb.options in tty.
  };

  # sops-nix: расшифровка при активации хостовым SSH-ключом, который на
  # лету превращается в age-ключ (публичные части — в .sops.yaml в корне
  # репозитория). Отдельную age-пару для хоста заводить не надо — одним
  # секретом меньше генерировать, бэкапить и терять. Расшифрованное
  # попадает в /run/secrets/<name> (tmpfs, исчезает при перезагрузке) и
  # никогда в /nix/store, который читаем всеми пользователями.
  #
  # Путь один и тот же на обоих хостах, но ключ у каждого свой — значит
  # каждый открывает только те файлы, в получателях которых он указан
  # (см. creation_rules в .sops.yaml).
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # Дефолт — то, что нужно обоим хостам. Секреты, которые нужны только
  # одному, объявляются в его hosts/<name>/default.nix с явным
  # sopsFile = ../../secrets/<name>.yaml.
  sops.defaultSopsFile = ../../secrets/common.yaml;

  # Инструменты для работы с секретами. Нужны на обоих хостах: sops —
  # редактирование/перешифровка, ssh-to-age — получить age-ключ из
  # хостового SSH-ключа (и при добавлении нового хоста в .sops.yaml, и
  # при разовой операции `sops updatekeys`), age — сгенерировать личный
  # ключ. До этого их в системе не было, и всё приходилось звать через
  # `nix shell nixpkgs#...`.
  environment.systemPackages = with pkgs; [
    sops
    age
    ssh-to-age
  ];

  security.doas.enable = true;
  security.sudo.enable = false;
  security.doas.extraRules = [{
    users = [ "nix" ];
    keepEnv = true;
    persist = true;
  }];

  # Host default.nix files add extraGroups on top of this.
  users.users.nix = {
    isNormalUser = true;
    shell = pkgs.fish;
  };
}
