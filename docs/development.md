# Development

## Structure

| Path | Owns |
| --- | --- |
| `shell/` | QML, assets, scripts, shader sources and shell tests |
| `hyprland/pangu/` | Minimal shell hooks and optional desktop preset |
| `hyprland/defaults.nix` | Preset defaults and generated Lua settings schema |
| `nix/package/` | Runtime wrapper, dependencies and build gates |
| `nix/modules/` | Public Home Manager and NixOS integration |
| `nix/lib/` | Mutable settings merge |
| `tests/` | Lua behavior and Nix module integration helpers |
| `scripts/` | Checkout development tools |

`shell/shell.qml` starts services and creates surfaces per screen. Backends
live in `shell/modules/services`; UI components consume them. `Config` owns
settings and must not import services. Compositor access goes through
`Compositor.qml`, and paths through `config/Paths.qml`.

Use `ConfigFile` for adapter-shaped JSON, `JsonStore` for dynamic-key JSON and
`GeneratedFile` for generated text. The latter reports completion after the
latest output is written, so consumers can reload safely. Settings panels use
snapshot/restore and beginEdit/save/endEdit for Apply and Discard. Keep one
drafting owner per file; system settings save independently. Update
`SettingsIndex.qml` when adding a searchable setting.

## Verification

```sh
nix fmt -- --ci
nix flake check --print-build-logs
```

The package runs JavaScript and Python tests, shell syntax checks, QML syntax
checks and shader compilation/validation. Flake checks also exercise the public
modules without any private NixOS configuration, mutable-settings merges,
standalone and preset Lua hooks, generated settings, runtime commands and
development-runner validation.
CI runs formatting and all checks. Only `x86_64-linux` is currently advertised
and tested; add another platform only after verifying its dependencies.

## Checkout runner

`nix run .#dev` uses the installed wrapper dependencies and Qt imports with
QML from the working directory's `shell/`. Pass another checkout directory as
`nix run .#dev -- /path/to/Pangu-Shell`. It refuses to start alongside an active
`pangu.service`, and compiles shader sources into ignored `.qsb` files first.
It does not install a service or alter the consuming flake's lock file.

For individual tests and shader tooling:

```sh
nix develop
bash scripts/rebake-shaders.sh
node shell/tests/test_services.js
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s shell/tests -v
```

Always compile shaders before running the checkout's full QML or shader tests.
The wrapper accepts `PANGU_SHELL_DIR` for development; ordinary startup uses its
immutable packaged source. `pangu run`, `lock` and `brightness` use IPC, while
`pangu reload` and `quit` control the installed service. Do not use service
restart commands to reload a manual development instance.

```sh
systemctl --user status pangu.service
journalctl --user -u pangu.service -b -n 100 --no-pager
hyprctl configerrors
pangu help
```

Package checks do not prove live interactions. After activating a consumer,
exercise multi-monitor surfaces, lock/unlock, suspend/resume, DDC brightness,
recording/replay, macros, wallpaper palettes and any desktop preset layouts.
Build the consuming system before activation; activation remains the user's
decision.
