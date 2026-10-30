{ config, pkgs, ... }:
{
  # Registers Obsidian's vault as an MCP server for Claude Code, pointed at
  # the built-in MCP endpoint the "Local REST API" community plugin
  # (coddingtonbear/obsidian-local-rest-api) ships -- no separate node/npx
  # or uv/uvx MCP server process needed, Obsidian serves it itself on
  # http://127.0.0.1:27123/mcp/ once "Enable HTTP server" is turned on in
  # the plugin's settings (loopback-only, so plain HTTP instead of its
  # self-signed HTTPS cert is fine here).
  #
  # `claude mcp add` writes into ~/.claude.json, which is Claude Code's own
  # live, constantly-mutated app state (cache, session data, etc.) -- not
  # something home-manager should own/overwrite wholesale. Instead this
  # activation script drives the same CLI the app itself uses, idempotently
  # (remove-then-add) every time home-manager activates, so the MCP entry
  # stays declared here rather than added once by hand and forgotten.
  #
  # The API key never touches the Nix store or git: it's decrypted by
  # sops-nix straight to /run/secrets/obsidian-api-key (owner nix, see
  # hosts/laptop/default.nix), and this script only ever reads it from
  # there at activation time.
  home.activation.obsidianMcp = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    # Referencing claude by full store path, not via PATH lookup: home-manager
    # activation scripts run with a minimal environment that doesn't reliably
    # include /etc/profiles/per-user/*/bin, which silently broke this the
    # first time around (command -v claude found nothing, script no-opped).
    CLAUDE=${pkgs.claude-code}/bin/claude
    if [ -r /run/secrets/obsidian-api-key ]; then
      $DRY_RUN_CMD "$CLAUDE" mcp remove obsidian-vault --scope user >/dev/null 2>&1 || true
      $DRY_RUN_CMD "$CLAUDE" mcp add --transport http obsidian-vault \
        http://127.0.0.1:27123/mcp/ \
        --header "Authorization: Bearer $(cat /run/secrets/obsidian-api-key)" \
        --scope user >/dev/null 2>&1 || true
    fi
  '';
}
