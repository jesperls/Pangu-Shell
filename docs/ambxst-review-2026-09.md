# Ambxst comparison and Pangu review

Reviewed on 2026-09-30 against Ambxst main at
[`3705f27`, version 1.3.9](https://github.com/Axenide/Ambxst/commit/3705f278f24a74718fc23772b47044e96701d53a).
This is a targeted source and integration review, with Pangu's running service
logs used to check actual errors. It is not an exhaustive interaction audit.

## Changes included

| Change | Reason and implementation |
| --- | --- |
| Shared OCR and QR selection | Adapted the [upstream selector idea](https://github.com/Axenide/Ambxst/commit/49e375721c0d4e8cf49acce29012762c0e3ceb25) to Pangu's existing frozen monitor images. Both tools now support region, window and screen selection, using the existing Tesseract and ZBar dependencies. Recognition images stay in the runtime directory and are removed after processing. |
| Capture after closing the notch | Adapted the [September 20 change](https://github.com/Axenide/Ambxst/commit/c5709276c0b25e06559bfeb62e6c2de999abdedb). All screenshot entry points share a delayed start after closing the active module. |
| Responsive sliders | Adopted the [upstream drag fix](https://github.com/Axenide/Ambxst/commit/0c2c8ac535be73407c7e9596e8fd880a4b911cfb): pointer drags update immediately; external value updates retain smoothing. |
| Working screenshot batch | The new QML workflow test reproduced `TypeError: Property 'flatMap' ... is not a function`. Qt's JavaScript engine does not support that call here. Building capture arguments with a loop fixes the failure that the existing Node test missed. |
| Capture lifecycle and placement | Cancelling Lens resets the next capture to a screenshot. An in-flight crop retains its operation when its selector closes. Screenshot previews use the saved monitor name, including full-monitor captures. Output directories are created before saving, and filenames include milliseconds. |
| EasyEffects presets | The live service reported `ReferenceError: Paths is not defined` for both preset commands. Importing `qs.config` restores directory lookup. |
| Popup reopening | A popup can reopen during its closing animation. The old close timer is cancelled and a deferred opening callback cannot grab focus after closing. |
| Tray object count | The tray previously constructed horizontal and vertical delegates simultaneously, including two menus per icon. One GridLayout now changes orientation while retaining one delegate per icon. |
| Screenshot preview processes | Annotating and deleting previews no longer allocate permanent QML Process objects on each click. Annotation uses the existing application launcher. |
| Unlock timer | Applied a positive minimum delay, following the [upstream change](https://github.com/Axenide/Ambxst/commit/db4f58be14bd8e5c07341ce2674ab990925f7ba3). This is a defensive adjustment; the review did not reproduce a live authentication failure with animations disabled. |
| Native tray overflow | Inspired by [upstream overflow](https://github.com/Axenide/Ambxst/commit/eb454836c39a0a167b2085450a029c158d4fc172). Pangu uses its own BarPopup and StateService, remembers hidden application IDs, and keeps middle-click activation. Shift-click moves an icon; the overflow menu offers a management list. Icon size, spacing and color style are searchable settings with Apply/Discard. |
| Shared wallpaper discovery | Inspired by [upstream symlink and tilde support](https://github.com/Axenide/Ambxst/commit/d5f9fd6232c5f0d98ea8033acc63fde89624382b). One Python scanner now defines the file list for the browser and preview worker. It preserves alias paths, handles uppercase extensions and BMP, guards symlink cycles, and reports JSON so newline filenames remain intact. Scans coalesce and ignore superseded directories. |
| Wallpaper gallery redesign | Pangu's native gallery uses landscape previews, optional filenames, adjustable card width, a small current-wallpaper badge, compact theme controls and empty results guidance. Keyboard selection survives filtering and file list changes. The dashboard preserves the requested startup tab. |

## Recommended next work

| Priority | Improvement | Evidence and fit |
| --- | --- | --- |
| High | Configurable clipboard retention | Ambxst [added a cap, encrypted storage and tmpfs mode](https://github.com/Axenide/Ambxst/commit/c581b36be5f14e91eef16cad167cf1d9d80de2e4). Pangu's database has no retention limit, and insertion reranks all unpinned entries. A configurable count/size limit would bound disk usage and indexing work. Preserve pinned entries and perform any binary-file cleanup after a successful transaction. Encryption needs an explicit key and migration design. |
| Medium | Shared Pomodoro service with a deadline | Clock creates a Pomodoro widget for each bar; each widget owns its timer and Spotify control. Timers can disagree across monitors, and decrementing once per Qt tick does not account for suspend or event-loop stalls. Put the timer and alarm in a singleton, calculate remaining time from a deadline, and decide explicitly whether sleep counts toward a session. |
| Medium | Stable tool action identifiers | ToolsMenu dispatches through English tooltip strings. Ambxst [changed recorder action matching on September 23](https://github.com/Axenide/Ambxst/commit/94e8ecf). Use stable identifiers before adding translations or changing labels. |
| Later | Native video wallpapers and live lockscreen video | Ambxst [moved from mpvpaper to QtMultimedia](https://github.com/Axenide/Ambxst/commit/a6627cc49bbe53c75c1c7526ed12ccaa3b8e06bd). Pangu's current path also owns tint shaders, mpv IPC synchronization and Wallpaper Engine handling. Prototype decode load, pause/fullscreen behavior, tinting and multi-monitor synchronization before replacing it. A static lockscreen frame remains a sensible low-cost default. |

Pangu already has monitor-specific fullscreen detection, an OSD instantiated
before its first event, persisted-state restoration, serialized DDC writes and
event-driven network controls. Those upstream areas are not useful wholesale
ports. Ambxst's Go supervisor and axctl integration would require changing
Pangu's service and compositor ownership; they are not necessary for the
features above.

## Nix integration and validation

The changes use existing runtime dependencies and add no public module options.
The consumer continues to own application choices, hardware, GTK/Qt integration
and the desktop preset settings in `~/nixos-config`.

Regression coverage includes a real headless Quickshell workflow with stubbed
capture and recognition programs, scaled-monitor crop arguments, cancellation,
temporary-image cleanup, popup reopening, and supplied-image recognition with
literal filenames and OCR languages. The packaged suite also checks QML syntax,
shaders, Python helpers, JavaScript services and shell syntax.

Run `nix fmt -- --ci` and `nix flake check`. Build the consumer with the checkout
as a temporary override, leaving its lock file unchanged:

```sh
nix build ~/nixos-config#nixosConfigurations.pangu.config.system.build.toplevel \
  --override-input pangu-shell path:/home/jesperls/Source/Pangu-Shell \
  --no-write-lock-file --no-link
```

The offscreen tests verify orchestration with stubbed programs. They do not
prove live OCR accuracy, Wayland selection/focus behavior, PAM authentication,
or mixed-scale physical monitor placement. After installing, check capture
from the launcher and Tools menu, cancel Lens then take a screenshot, reopen
popups quickly, drag sliders, and change the bar between horizontal and vertical.
Building alone does not activate the running session.

The gallery and tray pass was subsequently built and activated through the
consumer's `snus` workflow with user authorization. The gallery opened the
requested tab on its first call and generated all 24 regular previews alongside
10 Wallpaper Engine entries in the live collection. Tray management exposed a
hidden-delegate parent lookup error inside the real styled container; delegates
now refer to their explicit ID, and the headless fixture includes an internal
content container to cover that ownership boundary.
