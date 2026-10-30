# CLAUDE.md

Multi-host NixOS flake: `laptop` (ThinkPad X390) and `server` (headless EPYC 7402 + RTX 4070, dual-boot with Windows), plus a standalone installer ISO for the server. `forge` is a temporary third host (old PC's platform on the server's PSU) for heavy agent work — VMs under libvirt/VirtualBox/VMware plus docker, installed from a self-contained ISO that has its whole system baked in (`nix build .#forge-installer-iso`, no network or SSH needed), runbook [`docs/install-forge.md`](docs/install-forge.md); `server` stays inference-only. Two remote VPS, `ru-edge` and `nl-exit`, form the censorship-bypass tunnel — see **VPS** below. home-manager is a NixOS module, not standalone. User is `nix`.

**Detailed notes — architecture, per-host state, gotchas, secrets handling, distributed builds, open issues — are in [`docs/repo-notes.md`](docs/repo-notes.md). Read it before touching anything non-trivial.** The server install runbook is [`docs/install-server.md`](docs/install-server.md).

## Commands

Apply changes (needs a doas password — run in an interactive terminal, not from a tool call): `rebuild-switch` (fish alias for `nixos-rebuild switch --flake /home/nix/.nix#laptop --sudo`; also `rebuild-boot`, `rebuild-dry-activate`; the server has its own copies pointing at `#server`).

Verify without root:
```
nix flake check --no-build
nix build .#nixosConfigurations.laptop.config.system.build.toplevel --no-link --print-out-paths
```
`nix flake check` alone is not enough — it passes on configs that cannot build; always run the toplevel build too. Flakes see only git-tracked files, so `git add` new files before building.

## VPS: `ru-edge` + `nl-exit` (censorship-bypass tunnel)

Full history, decisions and pitfalls: **`docs/xray-bypass-notes.md`** (chronological log, newest at the end). Step-by-step install/ops: **`docs/install-vps.md`**. Read the log's last «ПЕРЕДАЧА» sections before touching this area.

- **Topology.** `ru-edge` (portal, RU, 1 GB RAM, public entry `cloud.example.com`) ⇄ `nl-exit` (bridge, NL). The reverse tunnel (xray VLESS reverse, `r-nl` portal / `r-in` bridge) is dialled from NL to RU, so all client traffic entering ru-edge exits in NL. Entries on ru-edge: xhttp+Reality (self-steal fallback to a decoy site), Vision, Hysteria2 (UDP 443), Shadowsocks-2022 (8388); plus a CDN path (CDN provider, zone delegated, `cloud.` → ru-edge directly, apex → CDN).
- **Code.** `hosts/{ru-edge,nl-exit}`, shared `modules/nixos/vpn/` (`base.nix`, `portal.nix`, `bridge.nix`, `subscription.nix` = `sub-gen` + nginx location on a secret path, `decoy.nix`, `settings.nix` = domains/ports/keys/IPs). Built with `mkVps` in `flake.nix` (no home-manager/desktop overlays). Secrets: `secrets/vps.yaml` (shared), `secrets/ru-edge.yaml`, `secrets/laptop.yaml`; VPS decrypt with their SSH host key. I (Claude) have no age admin key — sops edits are the user's.
- **Deploy: deploy-rs only** — `deploy .#ru-edge`, `.#nl-exit`, or `deploy .` (needs the user's sudo password, `interactiveSudo`; I can't enter it — prepare the branch/worktree, the user runs it). Magic rollback if SSH doesn't answer in 30 s. The old fish `deploy-vps` is unused. First install: `nixos-anywhere` (`--kexec` custom ZRAM image for 1 GB RAM), see install-vps.md.
- **Signing keys.** VPS accept only paths signed by `cache.nixos.org`, the server key, the laptop key (`vpn/base.nix` `trusted-public-keys`). A new signer in the closure (e.g. `cache.nixos-cuda.org`) ⇒ deploy the key first **on the old `flake.lock`**, only then the lock update, or `lacks a signature by a trusted key`.
- **Disk unlock.** LUKS + Clevis/Tang (Tang on the home server, reached from NL via a relay on ru-edge, port 7655). JWE files in `secrets/clevis/`; the Clevis key must be exactly 64 bytes with **no trailing newline**. Break-glass: `ssh -p 2222 root@<vps>` → `systemd-tty-ask-password-agent`.
- **Client side.** Subscription served at `https://cloud.example.com/<sub-path>/{laptop,phone}.{yaml,txt,b64}` (`sub-path` is a sops secret). Laptop uses mihomo (`modules/nixos/mihomo*.nix`: `subscriptions`, `subscriptionOrder`, `dl` download group, `xrayUpstream`, `libvirtSocks`); xray is disabled on the laptop. mihomo 1.19 bug: xhttp `download-settings` inherits the parent's Reality ⇒ `edge-split-cdn-down` needs an empty `reality-opts`.
- **Working rules for Claude sessions.**
  - My own API traffic goes through the live mihomo (`127.0.0.1:6080`, REST `:9090`): never switch the live `proxy` group to an untested node — test in a separate mihomo instance on another port.
  - Use `git worktree add` + absolute paths for edits (`EnterWorktree` fails from `~/Documents`); background jobs: no `pgrep -f` self-match, no heredocs inside `eval`.
  - Cloudflare speed tests return 403 above ~50 MB; SSH to NL goes via ru-edge and shares its rate-limit meter.
  - Verify with `nix build …toplevel` (see Commands), not `nix flake check` alone.

## Conventions

- Commit messages loosely follow `type(scope): summary`.
- When Claude makes commits in this repo, use a distinct author so they're distinguishable from the user's own, without touching git config: `git -c user.name="Claude" -c user.email="noreply@anthropic.com" commit -m "..."`. Push automatically after committing.
- The user is not a Nix/NixOS expert — parts of this config came from guides rather than deep familiarity with the module system. When touching something non-obvious (a systemd unit, a doas/sudo quirk, a module-merge behavior, a flake mechanism), explain briefly what it is and why, proportional to how non-obvious it is — don't just make the change silently.
- Keep `docs/repo-notes.md` updated as new non-obvious repo-specific facts come up in conversation (a gotcha hit while debugging, a design decision explained, a pattern worth reusing) — don't wait to be asked each time. Keep this file short; details go there.
