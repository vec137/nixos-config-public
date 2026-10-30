# secrets/

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) and encrypted
with [age](https://github.com/FiloSottile/age). The encryption policy lives in
`.sops.yaml` at the repo root — it lists the age public keys (one per host,
derived from each machine's SSH host key, plus a personal admin key) and the
`creation_rules` that decide which keys can decrypt which file.

The actual encrypted files (`vps.yaml`, `ru-edge.yaml`, `laptop.yaml`,
`server.yaml`, `common.yaml`, `clevis/*.jwe`, `xray/*.bin`) are **not included
in this public mirror**, even though their contents are encrypted at rest —
no point handing out ciphertext, key layout, or rotation history for no
reason. The modules under `modules/nixos/` and `hosts/*/` reference these
paths (e.g. `sops.secrets."ss-server-key"`) exactly as they do in the private
repo; only the files themselves are stripped here.
