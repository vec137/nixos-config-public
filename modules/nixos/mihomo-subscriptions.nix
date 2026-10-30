# Подписки для mihomo (modules/nixos/mihomo.nix) — одни и те же на ноутбуке и
# сервере. URL лежат в secrets/common.yaml (зашифрован на admin, laptop и
# server, см. .sops.yaml); здесь только соответствие «имя proxy-provider →
# ключ в sops».
#
# Чтобы добавить подписку:
#   1. `sops secrets/common.yaml` — добавить ключ с URL;
#   2. строка в subscriptions ниже;
#   3. ребилд ноутбука и сервера.
# Ключ в sops должен появиться ДО ребилда на ОБОИХ хостах, иначе
# sops-install-secrets не найдёт его и активация упадёт целиком
# ("the key ... cannot be found"). Имя провайдера видно в metacubexd
# (Proxy Providers) и не должно совпадать с именем узла.
#
# Подписка, нужная только одному хосту, задаётся в его hosts/<h>/default.nix
# (`services.mihomoBalancer.subscriptions.<имя> = ...`, это attrsOf — наборы
# сливаются), но тогда sopsFile для неё придётся переопределить через mkForce
# на весь хост: опция одна на модуль.
{
  services.mihomoBalancer = {
    sopsFile = ../../secrets/common.yaml;
    # Наша подписка с ru-edge — первой в списках (остальные по алфавиту).
    subscriptionOrder = [ "ruedge" ];
    subscriptions = {
      geodema = "mihomo-geodema";
      itdog = "mihomo-itdog";
      igareck = "mihomo-igareck";
      zieng2 = "mihomo-zieng2";
      ruedge = "mihomo-ruedge";
    };
  };
}
