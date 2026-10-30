{ config, lib, pkgs, ... }:
let
  liveSettings = "${config.home.homeDirectory}/.local/state/noctalia/settings.toml";
  repoSettings = "${config.home.homeDirectory}/.nix/modules/home/noctalia-full-config.toml";
in
{
  # Bootstrap: on a fresh machine (no live settings yet), seed noctalia from
  # the repo copy so it doesn't start from scratch. Never overwrites an
  # already-existing live config, since that's edited live via the GUI.
  #
  # The hassio plugin's ha_token has no env-var/external-file support (it's
  # read straight out of settings.toml by the plugin's Luau code), so the
  # repo copy only ever holds a "REDACTED" placeholder for it (see the export
  # service below) and the real value is re-asserted into the live file here
  # on every activation, from sops-nix's decrypted /run/secrets/ha-token.
  # This also self-heals if the placeholder ever ends up live (e.g. right
  # after a fresh-machine seed).
  home.activation.noctaliaSeedConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "${liveSettings}" ] && [ -e "${repoSettings}" ]; then
      mkdir -p "$(dirname "${liveSettings}")"
      cp "${repoSettings}" "${liveSettings}"
    fi
    if [ -e "${liveSettings}" ] && [ -r /run/secrets/ha-token ]; then
      $DRY_RUN_CMD ${pkgs.gnused}/bin/sed -i \
        "s|^ha_token = \".*\"|ha_token = \"$(cat /run/secrets/ha-token)\"|" \
        "${liveSettings}"
    fi
  '';

  # Auto-export: whenever noctalia's GUI writes settings.toml, mirror it into
  # the repo so the exported copy never goes stale -- except ha_token, which
  # gets redacted to a placeholder first so the real secret never lands in
  # git (it's re-injected from sops-nix on the next activation, see above).
  systemd.user.services.noctalia-config-export = {
    Unit.Description = "Mirror noctalia settings.toml into the nix config repo (secrets redacted)";
    Service = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "noctalia-config-export" ''
        ${pkgs.gnused}/bin/sed 's/^ha_token = ".*"/ha_token = "REDACTED"/' \
          "${liveSettings}" > "${repoSettings}"
      '';
    };
  };
  systemd.user.paths.noctalia-config-export = {
    Unit.Description = "Watch noctalia settings.toml for changes";
    Path.PathModified = liveSettings;
    Install.WantedBy = [ "paths.target" ];
  };
}
