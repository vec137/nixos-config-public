{ config, pkgs, ... }:
{
  # Two browser-automation MCP servers for Claude Code, deliberately kept
  # separate because they solve different problems:
  #
  #   playwright        - drives Playwright's *own* patched Firefox build in a
  #                       throwaway in-memory profile. No cookies, no logins,
  #                       no extensions. Use for scraping//fetching pages where
  #                       a real JS-executing browser is enough and the smaller
  #                       blast radius is the point.
  #   firefox-devtools  - Mozilla's official server, attached over Marionette
  #                       to an already-running LibreWolf in the dedicated
  #                       `mcp` profile declared in modules/home/misc.nix
  #                       (start it with the `librewolf-mcp` alias). Use when
  #                       a page genuinely needs a persistent session (logins,
  #                       sites that fingerprint/rate-limit anonymous
  #                       visitors).
  #
  # The `mcp` profile exists precisely so this never touches my-profile: an
  # MCP server with access to the everyday browser would inherit every logged-in
  # session in it at once (mail, git forges, banking), which is a much bigger
  # blast radius than any of this is worth. Keep logins in that profile to the
  # minimum a given task actually needs.
  #
  # Neither server can drive browser *chrome* or other extensions -- SmartProxy
  # included. Mozilla's `webextension` module only installs/uninstalls add-ons
  # by file or ID; it cannot toggle existing ones or open their popups. Proxy
  # routing therefore has to be configured on the server itself (see below),
  # not by flipping SmartProxy.
  home.packages = with pkgs; [
    playwright-mcp
    # firefox-devtools-mcp is not in nixpkgs, so it is fetched by npx at
    # runtime (needs Node >= 20.19; nixpkgs currently ships 24.x). This is the
    # one non-reproducible piece here: the first launch downloads into
    # ~/.npm and needs network. nodejs is worth having in PATH anyway.
    nodejs
  ];

  # Same approach as modules/home/obsidian-mcp.nix: `claude mcp add` writes to
  # ~/.claude.json, which is Claude Code's own mutable app state and must not
  # be owned wholesale by home-manager. Drive the CLI idempotently instead
  # (remove-then-add) so the servers stay declared here.
  home.activation.browserMcp = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    # Full store path, not a PATH lookup -- activation scripts run with a
    # minimal environment that does not reliably include
    # /etc/profiles/per-user/*/bin (see obsidian-mcp.nix for how that bit).
    CLAUDE=${pkgs.claude-code}/bin/claude

    # --- Playwright: own browser, disposable profile ---------------------
    # PLAYWRIGHT_BROWSERS_PATH points at the Nix-built browser bundle;
    # without SKIP_BROWSER_DOWNLOAD Playwright tries to fetch browsers into a
    # mutable directory at first run, which does not work here. Both are set
    # per-server rather than in home.sessionVariables on purpose: a global
    # entry is visible to every process in the session, which is exactly how
    # the old global HTTPS_PROXY leaked into cassette (see common.nix).
    $DRY_RUN_CMD "$CLAUDE" mcp remove playwright --scope user >/dev/null 2>&1 || true
    $DRY_RUN_CMD "$CLAUDE" mcp add playwright \
      -e PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers} \
      -e PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
      --scope user \
      -- ${pkgs.playwright-mcp}/bin/playwright-mcp \
         --browser firefox \
         --isolated \
      >/dev/null 2>&1 || true

    # No --proxy-server here yet, deliberately. Forcing every request through
    # the xray tunnel would break the other half of the SmartProxy setup --
    # sites that reject foreign exit IPs need to go out direct. Once the
    # SmartProxy rules are exported, translate the direct-connection list into
    # --proxy-bypass and add both flags above:
    #     --proxy-server socks5://127.0.0.1:3080 \
    #     --proxy-bypass "example.ru,another.ru" \

    # --- Mozilla official: real LibreWolf, dedicated profile -------------
    # --connect-existing, not --profile-path. Handed a directory that already
    # looks like a real profile, the server refuses to drive it ("It will NOT
    # be used directly") and instead launches its own browser in a nested
    # throwaway profile inside it (mcp.default/firefox_devtools_mcp_profile).
    # Nothing errors out -- every tool call just sees an empty browser, so the
    # mcp profile's tabs and logins are invisible and the persistent profile
    # this server exists for is silently bypassed. In connect-existing mode
    # the server launches nothing and attaches over Marionette to a browser
    # that is already up, which is what we actually wanted.
    #
    # Cost of the mode: the browser has to be running first, started with both
    # --marionette (the WebDriver control channel on 2828, the port dialled
    # below) and --remote-debugging-port -- that is what the `librewolf-mcp`
    # alias in fish.nix is for. With nothing listening on 2828 the tools fail
    # outright; there is no fallback to launching a browser.
    #
    # --firefox-path goes away with the launching. If this ever returns to
    # launch mode it has to be the ELF in lib/librewolf, not bin/librewolf --
    # see docs/repo-notes.md for the geckodriver reason, which is not obvious.
    $DRY_RUN_CMD "$CLAUDE" mcp remove firefox-devtools --scope user >/dev/null 2>&1 || true
    $DRY_RUN_CMD "$CLAUDE" mcp add firefox-devtools \
      --scope user \
      -- ${pkgs.nodejs}/bin/npx -y @mozilla/firefox-devtools-mcp@latest \
         --connect-existing \
         --marionette-port 2828 \
      >/dev/null 2>&1 || true
  '';
}
