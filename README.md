# Steam Linux Transparency

[Repository](https://github.com/NJMRgit/STLT) · [Releases](https://github.com/NJMRgit/STLT/releases)

A Millennium plugin that gives the Steam client **native per-pixel window transparency** on Linux, without using window opacity. The main window, Settings, Friends List, context menus and other Steam popups get 32-bit ARGB surfaces. The plugin never forces Big Picture; Steam's own Big Picture mode is supported.

Steam's Chromium (CEF) window is normally created as an opaque surface. Themes such as SpaceTheme implement Mica-style transparency with `rgba()` backgrounds, but on Linux those alpha values are composited against an opaque black surface, so the desktop never shows through.

This plugin changes the native window flags Steam uses when it creates the main window and its popups:

```
createflags |= Composited | TransparentParentWindow
```

That makes Steam create a 32-bit ARGB window, so the theme's alpha reveals the desktop. Text and images stay fully opaque.

## How it works

1. After Steam starts, the plugin backend patches `steamui/sp.js` on disk and backs up the original as `sp.js.millennium-original`.
2. It also patches `ubuntu12_64/steamwebhelper_sniper_wrap.sh`: it removes Steam's `-use_xcomposite_workaround` webhelper argument and adds `--default-background-color=00000000`. The running webhelper is restarted once so the flag takes effect. This fixes the opaque native window state that appears after a Steam UI reload.
3. The `sp.js` patch adds `Composited | TransparentParentWindow` to the main desktop window's `eCreationFlags`.
4. The frontend calls `SteamClient.Browser.RestartJSContext()` once. That reloads the Steam UI and recreates the main window and its popups with the patched flags.
5. Context menu popups are created with `Resizable | Composited | TransparentParentWindow` (`4194576`) instead of the original popup-menu flags. This makes them managed normal windows, so KWin's Glass/Blur effect can apply compositor blur when **Exclude menus** is off. The plugin also sets the same `createflags` attribute on the popup HTML. Menus may then get a normal window decoration instead of the borderless popup look.
6. The patched `sp.js` and webhelper wrapper stay in place, so later Steam UI reloads recreate the windows transparently. If Steam restores either file, the plugin reapplies the patch; a restored wrapper triggers one webhelper restart.
7. Disabling the plugin restores `sp.js` and the webhelper wrapper from their backups and reloads the UI.

Steam overwrites `sp.js` on a full client start or update, so the plugin reapplies the patch after each start. The plugin does not use Big Picture for recovery.

## Requirements

- Linux
- Millennium 3.6 or newer
- A theme with transparent backgrounds. For SpaceTheme, enable **Mica & Acrylic plugin support** and set **Mica Transparency**.
- Optional: a compositor blur effect (KWin Blur/BlurPlus) for a Mica-like blurred backdrop.

## Install from release

Download `steam-linux-transparency.star` from [Releases](https://github.com/NJMRgit/STLT/releases) and copy it to `~/.local/share/millennium/plugins/`. Enable **Steam Linux Transparency** in Millennium → Plugins, then restart Steam.

## Build from source

```bash
bun install
bun run build
```

Starlight installs the plugin to `~/.local/share/millennium/plugins/`. Enable **Steam Linux Transparency** in Millennium → Plugins, then restart Steam.

## Settings

- **Native window transparency** — patches `sp.js` and reloads the Steam UI.
- **Apply automatically on startup** — reapplies after a Steam start or UI reload if transparency is missing.
- **Reapply now** — applies the current setting immediately, including the webhelper fix.
- **Restart Steam** — fallback: fully restarts the Steam client if transparency is still wrong. The automatic webhelper fix normally makes this unnecessary.

## Notes

- The Steam UI reloads once after the plugin applies the patch. The window may flash/reload briefly; this is expected.
- Steam updates can change the minified `sp.js` layout. If transparency stops after an update, click **Reapply now** or disable/re-enable the plugin.
- The plugin does not use `_NET_WM_WINDOW_OPACITY`; it does not fade the whole window.
- v2.3.0 removes the continuous CDP polling loop that could trigger a Steam UI reload and recreate opaque windows.
- v2.4.0 fixes the native cause of opaque windows after a Steam UI reload. The webhelper wrapper now removes `-use_xcomposite_workaround` and sets `--default-background-color=00000000`; the plugin restarts the webhelper once when it applies the patch. This works without a full Steam client restart. **Restart Steam** remains as a fallback.
- v2.4.1 adds a theme-aware translucent Mica background to the Friends List's empty chat pane. The pane is natively transparent, but Steam paints no background there, so it looked black over a dark desktop. The layer uses the active theme's accent/background variables, keeps the window ARGB, and does not use whole-window opacity or screenshots.
- v2.4.2 added a native alpha watchdog. v2.4.4 removed it: the persistent Friends opacity was caused by Steam's own CSS backgrounds, not native alpha loss, and automatic restarts did not fix it.
- v2.4.4 fixes the real Friends List opacity. Steam's Friends UI paints `body` as opaque `rgb(0, 0, 0)` and uses opaque radial gradients on `.friendlistListContainer` and `.chatDialogs`. The plugin overrides those background layers with translucent theme gradients, so the existing ARGB window becomes genuinely transparent (verified 96.8% non-opaque) without restarting Steam.
- v2.4.3 extended the theme-aware Mica layer to the entire Friends window. v2.4.4 replaces the underlying opaque Friends CSS backgrounds, so the effect is genuine per-pixel transparency rather than an opaque themed window.
- Settings and Friends List are recreated with `Composited | TransparentParentWindow` after Big Picture exits, so their transparency survives the mode switch.
- After exiting Big Picture, the plugin restores the main window's `1010x600` minimum size and its previous desktop window size. This is built into the patched desktop window code, so it still works if the Steam UI reloads on exit.
- Settings, Friends List, context menus, and other Steam popup windows get the same flags. Existing popups may need to be reopened after the patch is applied.
