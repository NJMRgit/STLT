# Steam Linux Transparency

[Repository](https://github.com/NJMRgit/STLT) · [Releases](https://github.com/NJMRgit/STLT/releases)

<img width="2243" height="1392" alt="image" src="https://github.com/user-attachments/assets/fc2663d6-8c9f-4e87-8241-2dfea6da1b92" />

A Millennium plugin that gives the Steam client **native per-pixel window transparency** on Linux, without using whole-window opacity. The main window and Steam popups get 32-bit ARGB surfaces; a transparent Steam theme supplies the translucent background colors.

Steam's Chromium (CEF) window is normally opaque. This plugin changes Steam's native window-creation flags:

```text
createflags |= Composited | TransparentParentWindow
```

so the theme's alpha reveals the desktop instead of being composited against opaque black.

## How it works

1. The backend patches `steamui/sp.js` and backs up the original as `sp.js.millennium-original`.
2. It adds `Composited | TransparentParentWindow` to the main desktop window, Settings, Friends List, modal dialogs, and other Steam popups.
3. It also appends `--disable-features=CalculateNativeWinOcclusion` to `ubuntu12_64/steamwebhelper_sniper_wrap.sh`. Steam/CEF otherwise marks a re-opened Big Picture window as occluded and throttles it to about 20 FPS. The flag must come after Steam's own arguments, because Steam passes another `--disable-features` list that would override an earlier one. The webhelper restarts once to apply this change.
4. Context menu popups are created with `Resizable | Composited | TransparentParentWindow` (`4194576`) so a compositor can apply blur. Menus may get normal window decoration instead of Steam's borderless menu look.
5. A transparent Steam theme owns the actual background layers. v2.4.7 removed the plugin's Friends/Settings CSS overrides; the companion transparent QuickCSS theme now supplies them.
6. Disabling the plugin restores `sp.js` and the webhelper wrapper from their backups and reloads the UI.

Steam can overwrite `sp.js` or the webhelper wrapper on updates. The plugin reapplies them after a Steam start.

## Requirements

- Linux running Steam through X11 or XWayland.
- A running compositing manager that supports ARGB windows.
- Millennium 3.6 or newer.
- A transparent Steam theme. The default Steam theme needs a transparent QuickCSS theme; SpaceTheme also works with its Mica settings.
- Optional: a compositor blur effect (KWin Glass/BlurPlus, picom, etc.) for a Mica-like backdrop.

## Desktop / compositor compatibility

The ARGB flags are Steam/X11 window flags, not KDE-specific. They work with any compositor that honors depth-32 ARGB windows.

- **KDE Plasma/KWin**: tested here. KWin Glass/Blur can blur the result. The context-menu flags are specifically useful for KWin's menu blur.
- **GNOME/Mutter, Xfce, etc.**: the transparency flags should work, but other desktops are untested. Compositor blur is desktop-specific.
- **Wayland**: Steam currently runs through XWayland. Native Wayland Steam is not covered by these X11 flags.
- Without a compositing manager, transparent windows may render black.
- Context-menu decorations and focus behavior are controlled by the window manager.

## Optional glass QuickCSS theme

The plugin sets native ARGB window flags; it does not paint the Steam UI background. A transparent QuickCSS theme must replace Steam's opaque backgrounds.

The repository includes an optional glass theme based on Steam's default theme:

- File: [`themes/steam-default-glass.css`](themes/steam-default-glass.css)
- Requires Millennium QuickCSS.
- Designed for the Steam default theme, not SpaceTheme. The plugin's native transparency works with any transparent theme.

To use it, copy the contents of `themes/steam-default-glass.css` into **Millennium → Quick CSS** and save.

Millennium only watches `quick.css` while the Quick CSS editor is open. After saving, reopen the editor or reload the Steam desktop UI once (`SteamClient.Browser.RestartJSContext()`). A full Steam client restart is not required.

The theme targets the current Steam UI hashed class names, verified against Steam UI build `1792618285`. Steam UI updates can change those classes; selectors may then need updating.

## Install

Download `steam-linux-transparency.star` from [Releases](https://github.com/NJMRgit/STLT/releases), copy it to `~/.local/share/millennium/plugins/`, and enable **Steam Linux Transparency** in Millennium → Plugins.

Enabling the plugin can reload the Steam UI and, when the webhelper wrapper needs applying, restart the webhelper once. A full Steam client restart is not required for the transparency fix.

## Build from source

```bash
bun install
bun run build
```

Starlight installs the plugin to `~/.local/share/millennium/plugins/`.

## Settings

- **Native window transparency** — patches `sp.js` and the webhelper wrapper.
- **Apply automatically on startup** — reapplies after a Steam start or UI reload if transparency is missing.
- **Reapply now** — applies the current setting immediately.
- **Restart Steam** — last-resort fallback if the Steam client is in a bad native-window state.

## Known issues

- **Big Picture frame rate (fixed in v2.4.8)**: Steam/CEF's native window occlusion calculation could mark a re-entered Big Picture window as occluded and throttle it to about 20 FPS. The plugin now disables that calculation with a webhelper argument appended after Steam's own arguments. If the wrapper is overwritten, restart Steam or click **Reapply now**.
- **Steam updates**: the minified `sp.js` layout can change. If transparency stops after an update, click **Reapply now** or disable/re-enable the plugin.
- **Existing popups**: Settings/Friends opened before a patch may need to be reopened.
- **Friends chat pane**: the native window is transparent, but Steam's Friends CSS paints opaque backgrounds. The companion QuickCSS theme must override `body`, `.friendlistListContainer`, `.chatDialogs`, `.emptyChatDialogs`, and `.multiChatDialog`.
- The plugin does not use `_NET_WM_WINDOW_OPACITY`, whole-window opacity, screenshots, or a wallpaper fallback.

## Version notes

- v2.4.7: removed the plugin's Friends List CSS overrides; the transparent QuickCSS theme owns Friends/Settings backgrounds. Verified: main 62.48%, Friends 98.44%, Settings 98.13% non-opaque after a desktop UI reload only.
- v2.4.6: removed the automatic Big Picture UI reload; it could recreate windows opaque.
- v2.4.4/v2.4.2: removed the automatic webhelper opacity watchdog; it did not fix opaque CSS backgrounds.
- v2.4.0: webhelper wrapper fix; v2.3.0 removed the continuous CDP polling loop.
