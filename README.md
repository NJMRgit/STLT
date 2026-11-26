# Steam Linux Transparency

[Repository](https://github.com/NJMRgit/STLT) · [Releases](https://github.com/NJMRgit/STLT/releases)

<img width="2243" height="1392" alt="image" src="https://github.com/user-attachments/assets/fc2663d6-8c9f-4e87-8241-2dfea6da1b92" />

A Millennium plugin that gives the Steam client **native per-pixel window transparency**
on Linux, without whole-window opacity. The main window, Settings, Friends List, chats,
modals and menus get 32-bit ARGB surfaces; a transparent Steam theme supplies the
translucent background colours.

Steam's Chromium (CEF) window is normally opaque. Steam decides that per window, from the
window-create flags it passes when the window is opened:

```text
createflags |= Composited | TransparentParentWindow
```

With those bits set, the theme's alpha reaches the desktop instead of being composited
against opaque black.

## How it works

Steam opens every desktop window — main window, Settings, Friends List, menus, modals,
chat windows — through `window.open()` with a URL that carries
`?createflags=<Steam WindowFlags>`. The plugin wraps `window.open` and adds the two flags
to that URL:

| flag | value | effect |
| --- | --- | --- |
| `Composited` | `1 << 22` = `4194304` | ARGB surface |
| `TransparentParentWindow` | `1 << 8` = `256` | alpha actually reaches the compositor |

1. The hook runs in Millennium's shared JS context, which is the context that creates the
   main window — so the main window is created transparent from the first frame.
2. Child windows are created from the *main window's* JS context, so the plugin also hooks
   each popup's own `window` via `g_PopupManager` (`GetPopups` + `AddPopupCreatedCallback`).
   Settings, Friends, chats, modals and menus inherit the flags without any per-window code.
3. The flags are **added** to Steam's own flag set, never replaced. Steam's other bits carry
   the window type and focus behaviour; replacing them (as v2 did for menus, with `4194576`)
   turns menus into opaque, resizable toplevels that tiling window managers try to tile.
4. Nothing on disk is modified. `steamui/sp.js`, the CEF wrapper scripts and `config/` stay
   exactly as Valve shipped them, so there is nothing to re-apply after a Steam update and
   nothing to restore when the plugin is disabled.

The flag values are a native CEF/Steam ABI and `window.open` is a DOM API, so neither is
affected by Steam UI bundle updates (which rename every minified local and every CSS module
class on each build).

### Why not patching `sp.js` (v2, deprecated)

Up to v2.4.8 the plugin rewrote `steamui/sp.js` with five exact string anchors and patched
`ubuntu12_64/steamwebhelper_sniper_wrap.sh` to add a CEF occlusion flag. That approach:

- broke on every Steam UI update (all five anchors were gone by UI build `1794536281`),
- needed a UI reload after patching, and could leave `sp.js` half-patched,
- is impossible on the SteamRT3 client, which spawns `steamwebhelper` directly instead of
  through the wrapper, and whose pressure-vessel container has no `ps`/`pgrep` — the helper
  that detected the flags silently reported "not applied" forever,
- has no settings to configure anyway, so the whole backend, the settings UI, the restart
  watchdog and the log file are gone in v3.

## Requirements

- Linux running Steam through X11 or XWayland.
- A compositing manager that supports ARGB windows (KWin, Mutter, picom, …).
- Millennium 3.6 or newer (3.7 tested).
- A transparent Steam theme. For the default Steam theme use the
  [glass Quick CSS theme](themes/steam-default-glass.css) in this repository; SpaceTheme
  also works with its Mica settings.

## Install

1. Download `steam-linux-transparency.star` from [Releases](https://github.com/NJMRgit/STLT/releases).
2. Drop it in `~/.local/share/millennium/plugins/`.
3. Enable **Steam Linux Transparency** in Millennium → Plugins, then reload the Steam UI
   (or restart Steam) so the main window is created with the new flags.

There are no settings: the plugin has nothing to toggle.

## Optional glass Quick CSS theme

The plugin only sets native window flags; it does not paint Steam's background. A
transparent theme must supply the translucent colours.

- File: [`themes/steam-default-glass.css`](themes/steam-default-glass.css)
- Requires Millennium Quick CSS.
- Targets the default Steam theme (not SpaceTheme).

Copy the file's contents into **Millennium → Quick CSS** and save. Its class names track
Steam's hashed CSS modules, so they may need refreshing after a large Steam UI update.

## Menus, tiling and blur

Menus keep their own flag set plus the two transparency bits, so they stay popups: tiling
scripts (karousel and friends) leave them alone. The trade-off is that a compositor will
only blur them if it blurs popups/menus — e.g. `better-blur-dx` with `BlurMenus` and
`BlurNonMatching` enabled.

Because the glass theme tints menus at 20%, which is invisible when nothing blurs behind
them, the plugin floors big menu surfaces at `MENU_MIN_ALPHA` (0.38 in
`frontend/index.ts`). Lower it towards `0.2` for a more transparent look if your compositor
blurs menus; set it to `0` to leave the theme value untouched.

## Build from source

```bash
bun install
bun run build
```

Starlight writes `steam-linux-transparency.star` and installs it into
`~/.local/share/millennium/plugins/`.

## Compatibility

- Verified on Steam UI build `1794536281` (SteamRT3 client) and Millennium 3.7.0, KDE Plasma
  6 / KWin, both windowed and Big Picture.
- Windows that must stay opaque (notification toasts, `desktopoverlay_*`/game overlays, VR
  overlays) are skipped by name.
- Without a compositing manager, ARGB windows can render black; that is a compositor
  limitation, not something the plugin can work around.
- Native Wayland Steam is not covered: these are X11 create flags, and Steam currently runs
  through XWayland.

## Migration from 2.x

v3 is a rewrite, not an increment. Uninstall the old plugin, delete any stale
`steamui/sp.js.millennium-original` backup if a v2 install left one behind, install the v3
`.star`, and reload the UI. The old plugin's settings (native transparency / auto-apply)
no longer exist.
