# Config structure
Config mostly uses dendritic pattern, each part is splitted into modules.\
\
On the top you have flake.(nix|lock), agents stuff (AGENTS|CLAUDE).md and the following directories:
- `hosts/` - per-host configs (default.nix, etc) - essential parts, included modules - currently laptop, server, forge, ru-edge, nl-exit, installer & installer-forge
- `modules/` - is generally splitted into _nixos_ and _home_ (managed by home-manager) - anything hosts would ever need goes there
- `pkgs/` - some packages not yet in nixpkgs wrapped by agents
- `secrets/` - SOPS secrets directory, referenced in modules - API keys, public/private pairs for several services and some other stuff that won't go public in clear text
- `ssh/`, `misc/`, `xray/` - git ignored, they keep some configs I won't want to go even sops encrypted (maybe will be implemented later)

These configs and modules are highly personalized and likely won't be suitable for others, but I hope some parts of it may become useful to someone.
