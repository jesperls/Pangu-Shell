# Working on Pangu

Read `README.md`, `docs/configuration.md` and `docs/development.md` before
changing integration or packaging. Update documentation before changing ownership
or the public module interface.

Shell sources belong in `shell`; Hyprland Lua belongs in `hyprland/pangu`.
Nix packages, modules and checks belong in `nix`. Keep machine-specific hardware,
applications and private option namespaces out of the reusable modules.

Comment only traps, ordering constraints and workarounds, in one line at the
point of confusion. Preserve shebangs and `//@ pragma` lines.

Run `nix fmt -- --ci` and `nix flake check` before committing. When changing a
consumer, also build its desktop system. Building does not activate a session.
