{ config, pkgs, ... }:
{
  # OmniRoute (https://github.com/diegosouzapw/OmniRoute) as an MCP server
  # for Claude Code -- lets it delegate simple/cheap sub-tasks to free-tier
  # models instead of burning paid usage. OmniRoute ships its own flake.nix,
  # but that flake only exposes a devShell for hacking on OmniRoute's *own*
  # source (nodejs_22 + `npm install`), not an installable package -- there
  # is nothing in it to reference from home.packages.
  #
  # Not packaged from source here either: it's a ~22k-file npm package whose
  # postinstall scripts fetch/build native binaries (a TLS fingerprint
  # client, sharp, onnxruntime for its local compression model, keytar),
  # which cannot work inside Nix's sandboxed, network-isolated build.
  #
  # Deliberately NOT `npx -y omniroute --mcp` either (the approach used for
  # firefox-devtools-mcp in browser-mcp.nix), even though that also works:
  # `npx`/`npm exec` does a registry metadata lookup before every single
  # invocation, and that lookup was observed to hang indefinitely (TCP
  # connection established, response never arrives, no timeout) -- would
  # make every new Claude Code session's MCP startup a coin flip. Installing
  # once with `npm install -g` and pointing straight at the resulting binary
  # skips that lookup entirely; the tradeoff is a manual reinstall to pick up
  # new OmniRoute versions instead of npx's automatic "latest each time".
  #
  # Requires Node >=22.22.2 <23 or >=24.0.0 <27 -- nixpkgs currently ships
  # 24.19.0 here, which fits. `--mcp` runs OmniRoute in stdio MCP mode (spawned
  # fresh per Claude Code session, no persistent service needed); the HTTP
  # gateway + dashboard mode (`omniroute` alone, port 20128) is a different,
  # heavier integration path not used here.
  #
  # One-time manual steps this module cannot do for you (need network, and
  # the second is interactive -- neither belongs in an activation script):
  #   npm config set prefix ~/.npm-global   # nodejs's own prefix is the
  #                                          # read-only /nix/store
  #   npm install -g --allow-scripts=omniroute,keytar,onnxruntime-node,tls-client-node,sharp,@parcel/watcher,@swc/core,protobufjs,koffi,esbuild omniroute@3.8.50
  #   npm-global/bin/omniroute setup        # configure providers/API keys
  # State (including the API keys) lives under ~/.omniroute, outside
  # home-manager's control. Re-run the npm install line to upgrade.
  home.packages = [ pkgs.nodejs ];

  # So `omniroute` (doctor/chat/serve/...) is callable by name once the
  # global install above has been done, not just via the full path the MCP
  # registration below uses. home-manager writes this to
  # ~/.config/environment.d/10-home-manager.conf, which systemd --user only
  # reads once at its own manager-process startup -- see niri.service note
  # in docs/repo-notes.md for why a plain relogin can still serve a stale PATH here
  # with lingering enabled, and how to force it (systemctl --user
  # set-environment PATH=...).
  home.sessionPath = [ "${config.home.homeDirectory}/.npm-global/bin" ];

  # Same pattern as browser-mcp.nix / obsidian-mcp.nix: `claude mcp add`
  # writes to ~/.claude.json, Claude Code's own mutable app state, so this
  # drives the CLI idempotently (remove-then-add) on every activation
  # instead of home-manager owning that file. Only registers the server if
  # the one-time global install above has actually been done.
  #
  # OMNIROUTE_API_KEY is decrypted by sops-nix straight to
  # /run/secrets/omniroute-api-key (owner nix, see hosts/laptop/default.nix)
  # and only ever read from there at activation time -- same handling as
  # obsidian-api-key, never touches the Nix store or git. Without it,
  # management-ish MCP tool calls (health/quota/etc.) 401 even though the
  # server itself is reachable -- confirmed via `omniroute doctor`, which
  # separately accepts a local machine token for plain CLI use but that
  # token isn't shared with the MCP stdio subprocess.
  home.activation.omnirouteMcp = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    CLAUDE=${pkgs.claude-code}/bin/claude
    OMNIROUTE_BIN="${config.home.homeDirectory}/.npm-global/bin/omniroute"

    if [ -x "$OMNIROUTE_BIN" ]; then
      $DRY_RUN_CMD "$CLAUDE" mcp remove omniroute --scope user >/dev/null 2>&1 || true
      if [ -r /run/secrets/omniroute-api-key ]; then
        $DRY_RUN_CMD "$CLAUDE" mcp add omniroute \
          --scope user \
          -e OMNIROUTE_API_KEY="$(cat /run/secrets/omniroute-api-key)" \
          -- "$OMNIROUTE_BIN" --mcp \
          >/dev/null 2>&1 || true
      else
        $DRY_RUN_CMD "$CLAUDE" mcp add omniroute \
          --scope user \
          -- "$OMNIROUTE_BIN" --mcp \
          >/dev/null 2>&1 || true
      fi
    fi
  '';
}
