# Steam Linux Transparency

[Repository](https://github.com/NJMRgit/STLT) · [Releases](https://github.com/NJMRgit/STLT/releases)

A Millennium plugin that gives the Steam client **native per-pixel window transparency** on Linux, without using whole-window opacity. The main window and Steam popups get 32-bit ARGB surfaces; a transparent Steam theme supplies the translucent background colors.

Steam's Chromium (CEF) window is normally opaque. This plugin changes Steam's native window-creation flags:

```text
createflags |= Composited | TransparentParentWindow
```

so the theme's alpha reveals the desktop instead of being composited against opaque black.

## How it works

1. The backend patches `steamui/sp.js` and backs up the original as `sp.js.millennium-original`.
2. It adds `Composited | TransparentParentWindow` to the main desktop window, Settings, Friends List, modal dialogs, and other Steam popups.
3. It also patches `ubuntu12_64/steamwebhelper_sniper_wrap.sh`: it removes Steam's `-use_xcomposite_workaround` webhelper argument and adds `--default-background-color=00000000`. The webhelper can be restarted once to apply that wrapper change.
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

## Companion QuickCSS theme

The plugin handles native ARGB windows; it does not paint the Steam UI background. A transparent QuickCSS theme must replace the opaque Steam backgrounds. The default-theme QuickCSS used here lives at:

```text
~/.config/millennium/quick.css
```

It covers the main library/sidebar, Steam Settings, Friends List body/list/header/tabs/footer, and the Friends right chat pane. The important Friends selectors are:

```css
html.MillenniumWindow_FriendsList body,
html.MillenniumWindow_FriendsList .friendlistListContainer {
    background: rgba(23, 29, 37, 0.2) !important;
}

html.MillenniumWindow_FriendsList .friendListHeaderContainer,
html.MillenniumWindow_FriendsList .chatDialogs,
html.MillenniumWindow_FriendsList .emptyChatDialogs,
html.MillenniumWindow_FriendsList .multiChatDialog {
    background: transparent !important;
}
```

Millennium only watches `quick.css` while the Quick CSS editor is open. After editing it, reopen the editor or reload the Steam desktop UI once (`SteamClient.Browser.RestartJSContext()`) so all documents re-read it.

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

- **Big Picture frame rate**: repeatedly entering Big Picture can become low-FPS until Steam is restarted. This is a Steam client/GPU state issue, not fixed by this plugin.
- **Steam updates**: the minified `sp.js` layout can change. If transparency stops after an update, click **Reapply now** or disable/re-enable the plugin.
- **Existing popups**: Settings/Friends opened before a patch may need to be reopened.
- **Friends chat pane**: the native window is transparent, but Steam's Friends CSS paints opaque backgrounds. The companion QuickCSS theme must override `body`, `.friendlistListContainer`, `.chatDialogs`, `.emptyChatDialogs`, and `.multiChatDialog`.
- The plugin does not use `_NET_WM_WINDOW_OPACITY`, whole-window opacity, screenshots, or a wallpaper fallback.

## Version notes

- v2.4.7: removed the plugin's Friends List CSS overrides; the transparent QuickCSS theme owns Friends/Settings backgrounds. Verified: main 62.48%, Friends 98.44%, Settings 98.13% non-opaque after a desktop UI reload only.
- v2.4.6: removed the automatic Big Picture UI reload; it could recreate windows opaque.
- v2.4.4/v2.4.2: removed the automatic webhelper opacity watchdog; it did not fix opaque CSS backgrounds.
- v2.4.0: webhelper wrapper fix; v2.3.0 removed the continuous CDP polling loop.
