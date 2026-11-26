/**
 * Steam Linux Transparency — Millennium plugin frontend.
 *
 * Steam creates every desktop window (main window, Settings, Friends List,
 * menus, modals, chat windows) by calling `window.open()` on a URL that
 * carries `?createflags=<Steam WindowFlags>`. Those flags decide whether CEF
 * gets an ARGB surface it can paint alpha into, which is what makes per-pixel
 * transparency possible.
 *
 *   WindowFlags.Composited              = 1 << 22 = 4194304
 *   WindowFlags.TransparentParentWindow = 1 << 8  = 256
 *
 * The flags are always *added* to the set Steam asked for, never replaced:
 * Steam's own bits carry the window type and focus behaviour, and dropping
 * them turns menus into opaque, resizable toplevels that tiling window
 * managers (karousel and friends) then try to tile.
 *
 * This frontend runs in Millennium's shared JS context, which is the context
 * that creates the main window. Child windows are created from the main
 * window's own JS context, so the hook is also installed into every popup's
 * window object, and into new ones as they appear.
 */

declare const g_PopupManager: any;

const WANT_FLAGS = (1 << 22) | (1 << 8);

/**
 * Toasts and in-game/VR overlays are composited by their host surface; forcing
 * transparency on them breaks them. These are Steam's own popup names.
 */
const SKIP_WINDOW_NAME = /^(notificationtoasts_|desktopoverlay_|gamepadoverlay|overlay_|vr_|RemoteVideo|VRNotification)/i;

/** Windows whose background layers we make translucent: dialogs and lists. */
const DIALOG_WINDOW = /MillenniumWindow_(Settings|FriendsList)|ModalDialog|FriendsList/i;

/**
 * Context menus keep their own ARGB surface, but the glass theme tints them at
 * 20% — invisible when the compositor does not blur behind menus. `0` leaves
 * the theme value untouched.
 */
const MENU_WINDOW = /MillenniumWindow_ContextMenu|ContextMenuPopupBody|ContextMenuPopup/i;
const MENU_MIN_ALPHA = 0.38;

type AnyWindow = Window & typeof globalThis & Record<string, any>;

function rewriteCreateFlags(url: unknown, name: unknown): unknown {
	if (typeof url !== 'string' || url.length === 0) return url;
	if (!/[?&]createflags=/.test(url)) return url;
	if (name && SKIP_WINDOW_NAME.test(String(name))) return url;

	return url.replace(/([?&]createflags=)(\d+)/, (_match, prefix, value) =>
		prefix + ((Number.parseInt(value, 10) | WANT_FLAGS) >>> 0),
	);
}

/** Install the createflags hook into a window object (same-origin windows only). */
function hookWindow(targetWindow: AnyWindow) {
	try {
		if (!targetWindow || targetWindow.__stltOpenHooked) return;
		const nativeOpen = targetWindow.open;
		if (typeof nativeOpen !== 'function') return;

		const wrapped = function stltOpen(url?: string, name?: string, features?: string) {
			let target: any = url;
			try {
				target = rewriteCreateFlags(url, name);
			} catch (error) {
				console.warn('[STLT] createflags rewrite failed:', error);
			}
			return nativeOpen.call(targetWindow, target, name, features);
		};
		wrapped.__stltPatched = true;

		targetWindow.open = wrapped as typeof targetWindow.open;
		targetWindow.__stltOpenHooked = true;
	} catch (error) {
		console.warn('[STLT] could not hook window.open:', error);
	}
}

/* -------------------------------------------------------------------------- *
 * Surface styling.
 *
 * Window surfaces are identified by role — the large opaque background layers —
 * instead of Steam's hashed CSS-module class names, so a client update degrades
 * to "no change" rather than to wrong colours.
 *
 * Styling is deliberately cheap: `getComputedStyle` over a whole menu on every
 * mutation is what makes menus stutter, so elements are styled once and
 * remembered, and menu documents are only scanned a fixed number of times.
 * -------------------------------------------------------------------------- */

const styledDocuments = new WeakSet<Document>();

function styleDocument(doc: Document) {
	if (!doc || !doc.documentElement || styledDocuments.has(doc)) return;

	try {
		const win = doc.defaultView as AnyWindow | null;
		if (!win) return;

		const htmlClasses = doc.documentElement.className || '';
		const bodyClasses = doc.body?.className || '';
		const isMenu = MENU_WINDOW.test(htmlClasses) || MENU_WINDOW.test(bodyClasses);
		const isDialog = DIALOG_WINDOW.test(htmlClasses) || DIALOG_WINDOW.test(bodyClasses);
		if (!isMenu && !isDialog) return;

		styledDocuments.add(doc);

		const parseColor = (element: Element): [string, string, string, number] | null => {
			const match = win
				.getComputedStyle(element)
				.backgroundColor.match(/^rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s/]+([\d.]+))?\s*\)$/);
			if (!match) return null;
			const [, r, g, b, alpha = '1'] = match;
			return [r, g, b, Number(alpha)];
		};

		const isBig = (element: Element) => {
			const rect = element.getBoundingClientRect();
			return rect.width * rect.height >= win.innerWidth * win.innerHeight * 0.25;
		};

		const styleMenuSurface = (element: Element) => {
			if (!MENU_MIN_ALPHA || !isBig(element)) return;
			const color = parseColor(element);
			if (!color) return;
			const [r, g, b, alpha] = color;
			if (alpha >= MENU_MIN_ALPHA) return;
			(element as HTMLElement).style.setProperty('background-color', `rgba(${r}, ${g}, ${b}, ${MENU_MIN_ALPHA})`, 'important');
		};

		const styleDialogSurface = (element: Element) => {
			if (!isBig(element)) return;
			const color = parseColor(element);
			if (!color) return;
			const [r, g, b, alpha] = color;
			if (alpha < 1) return; // already translucent
			(element as HTMLElement).style.setProperty('background-color', `rgba(${r}, ${g}, ${b}, 0.2)`, 'important');
		};

		const pass = (firstPass: boolean) => {
			if (doc !== (win.document ?? null)) return;

			if (firstPass && isDialog) {
				for (const element of [doc.documentElement, doc.body]) {
					(element as HTMLElement | null)?.style?.setProperty('background-color', 'transparent', 'important');
				}
			}

			for (const element of Array.from(doc.querySelectorAll('body *, html, body'))) {
				const node = element as HTMLElement & { __stltDone?: boolean };
				if (node.__stltDone) continue;
				node.__stltDone = true;
				if (isMenu) styleMenuSurface(element);
				else styleDialogSurface(element);
			}
		};

		const firstPass = () => pass(true);
		if (doc.readyState === 'loading') doc.addEventListener('DOMContentLoaded', firstPass, { once: true });
		else firstPass();

		/* Menus repaint on hover; re-scanning on every mutation made them stutter. */
		for (const delay of [400, 1200, 2500]) win.setTimeout(() => pass(false), delay);

		/* Dialogs mount late and re-render; watch them, but debounced. */
		if (isDialog) {
			let queued = false;
			const root = doc.body || doc.documentElement;
			if (root) {
				new win.MutationObserver(() => {
					if (queued) return;
					queued = true;
					win.setTimeout(() => {
						queued = false;
						pass(false);
					}, 150);
				}).observe(root, { subtree: true, childList: true });
			}
		}
	} catch (error) {
		console.warn('[STLT] surface styling failed:', error);
	}
}

/* -------------------------------------------------------------------------- */

function handlePopup(popup: any) {
	if (!popup) return;
	if (!popup.window) {
		/* Some popups exist before their window object does. */
		setTimeout(() => handlePopup(popup), 300);
		return;
	}
	hookWindow(popup.window as AnyWindow);
	if (popup.window.document) styleDocument(popup.window.document);
}

/* 1. This context creates the main window at startup. */
hookWindow(window as AnyWindow);

/* 2. Adopt the windows Steam already created, and 3. every future one. */
try {
	const popupManager = typeof g_PopupManager !== 'undefined' ? g_PopupManager : (window as AnyWindow).opener?.g_PopupManager;
	if (popupManager) {
		const existing = popupManager.GetPopups?.();
		if (existing) for (const popup of Array.from(existing) as any[]) handlePopup(popup);

		popupManager.AddPopupCreatedCallback?.((popup: any) => handlePopup(popup));
	} else {
		console.warn('[STLT] popup manager unavailable; only this context is hooked');
	}
} catch (error) {
	console.warn('[STLT] popup manager hook failed:', error);
}

console.log('[STLT] runtime transparency hook installed');
