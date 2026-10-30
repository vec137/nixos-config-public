# Релей Tang на ru-edge для nl-exit: TCP-проброс tangRelayPort → home:tangPort.
#
# Зачем. Прямой путь NL → дом теряет потоки: 2026-10-09 из initrd NL до Tang
# доходило 13 запросов из 20 (и ещё хуже в другие минуты), ответы Tang (200 на
# стороне дома) до NL не добирались — clevis не успевал разблокировать диск за
# 2 минуты. Путь NL → ru-edge (20/20) и ru-edge → дом (20/20) чистые, поэтому
# NL ходит за ключом через ru-edge.
#
# Безопасность та же, что у самого Tang: он ключа не знает, а JWE бесполезен без
# него. Релей — чистый TCP, ничего не расшифровывает и не хранит. Порт открыт
# ТОЛЬКО для IP nl-exit; на стороне дома Tang и так пускает только IP обоих VPS
# (IPAddressAllow), в том числе этот.
#
# Ограничение: релей работает, пока ru-edge загружен. Если оба VPS ребутятся
# одновременно, NL не достанет ключ и останется на break-glass SSH (порт 2222).
{ config, lib, ... }:
let
  s = import ./settings.nix;
  port = toString s.tangRelayPort;
in
{
  systemd.sockets.tang-relay = {
    wantedBy = [ "sockets.target" ];
    listenStreams = [ port ];
  };

  systemd.services.tang-relay = {
    description = "TCP relay to Tang (home) for nl-exit";
    requires = [ "tang-relay.socket" ];
    after = [ "tang-relay.socket" ];
    serviceConfig = {
      ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd --exit-idle-time=2min ${s.home.ip}:${toString s.home.tangPort}";
      DynamicUser = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    };
  };

  # Порт — только для nl-exit. Правило в той же таблице, что и ssh в base.nix.
  networking.firewall.extraInputRules = ''
    ip saddr ${s.hosts.nl-exit} tcp dport ${port} accept
  '';
}
