/* aura-glass window-menu blur toggle, and a small D-Bus bridge for the
 * settings window's per-app blur page.
 *
 * The per-app blur allow/block list Blur My Shell reads is otherwise editable
 * in exactly two places: --app-blur-allow/--app-blur-block on install.sh, and
 * the Per-app blur page in the aura-glass settings window. Both mean leaving
 * the window you actually want to toggle. This puts the same question where
 * it gets asked — right-click the titlebar, "Blur This App" — by monkeypatching
 * WindowMenu._buildMenu the way Just Perfection's screenshotInWindowMenuShow
 * already does in this project's own extension set.
 *
 * Ships no schema of its own. It reads and writes Blur My Shell's
 * org.gnome.shell.extensions.blur-my-shell.applications directly — 'blur',
 * 'enable-all', 'whitelist', 'blacklist' — the same keys apply_app_blur in
 * lib/steps-dconf.sh writes, and mirrors the change into the same memo files
 * ($CONF_DIR/app-blur-allow, app-blur-block) that install.sh reads back on
 * every later run. Skipping that mirror would mean a toggle here holding
 * only until the next ./install.sh, which reads the stale memo over dconf.
 *
 * Adds nothing at all when Blur My Shell's schema cannot be found, or when
 * applications/blur is off: a menu item that provably does nothing is worse
 * than no menu item.
 *
 * The D-Bus service (io.github.DevWebeloper.AuraGlass) is what the settings
 * window's Per-app blur page uses for "Open now": an unprivileged GTK app has
 * no other way, on Wayland, to know what windows exist. It answers ListWindows,
 * and fires WindowsChanged when the answer to ListWindows would differ. It is
 * exported whenever the extension is enabled, independent of whether Blur My
 * Shell is present — the settings window is what decides whether to call it, by
 * whether the bridge answers at all.
 */

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';
import {WindowMenu} from 'resource:///org/gnome/shell/ui/windowMenu.js';
import {Extension, gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';

const BMS_UUID = 'blur-my-shell@aunetx';
const BMS_SCHEMA_ID = 'org.gnome.shell.extensions.blur-my-shell.applications';
const BMS_PANEL_SCHEMA_ID = 'org.gnome.shell.extensions.blur-my-shell.panel';
const BMS_CORE_SCHEMA_ID = 'org.gnome.shell.extensions.blur-my-shell';

// Pinned back onto the whitelist by every install.sh run (app_blur_pin_allow
// in lib/steps-dconf.sh) — the same string is duplicated in
// gui/aura_glass_settings.py (SELF_WM_CLASS) and checked against this one by
// tools/check-app-blur-lists.sh.
const SELF_WM_CLASS = 'io.github.DevWebeloper.AuraGlassSettings';

const DBUS_NAME = 'io.github.DevWebeloper.AuraGlass';
const DBUS_PATH = '/io/github/DevWebeloper/AuraGlass';
const DBUS_IFACE = `
<node>
  <interface name="${DBUS_NAME}">
    <method name="ListWindows">
      <arg type="a(ssu)" direction="out" name="windows"/>
    </method>
    <signal name="WindowsChanged"/>
  </interface>
</node>`;

// Mirrors Blur My Shell's own components/applications.js wildcardToRegex:
// escape every regex metacharacter except * and ?, anchor at both ends,
// * -> .*, ? -> ., case-insensitive. Brackets are escaped rather than left to
// form a character class, so [abc] matches the three literal characters —
// this has to agree with that function exactly, or this toggle and the
// allow/block list in the settings window would disagree about what a
// pattern covers. lib/steps-dconf.sh (app_blur_covers_self) and
// gui/aura_glass_settings.py (pattern_matches) are the other two mirrors.
const _regexCache = new Map();
function wildcardToRegex(pattern) {
    let re = _regexCache.get(pattern);
    if (!re) {
        const escaped = pattern
            .replace(/[.+^${}()|[\]\\]/g, '\\$&')
            .replace(/\*/g, '.*')
            .replace(/\?/g, '.');
        re = new RegExp(`^${escaped}$`, 'i');
        _regexCache.set(pattern, re);
    }
    return re;
}

function matchesAny(patterns, wmClass) {
    return patterns.some(p => p.trim() !== '' && wildcardToRegex(p).test(wmClass));
}

function matchesAnyClass(patterns, classes) {
    return classes.some(c => matchesAny(patterns, c));
}

// Mirrors patches/blur-my-shell-subwindows.patch's window_classes: a window's
// own wm_class and GTK application id, then the same two for each window up
// its transient-for chain — so right-clicking a dialog's titlebar toggles the
// app it belongs to, and the checkbox reads as checked when that app is
// blurred, not only when the dialog's own (often different, sometimes empty)
// class happens to be on the list. Bounded and cycle-guarded for the same
// reason the patch's copy is: transient-for loops are malformed but a client
// can still set one.
function windowClasses(window) {
    const classes = [];
    const push = v => { if (v && !classes.includes(v)) classes.push(v); };

    push(window.get_wm_class());
    push(window.get_gtk_application_id());

    const seen = new Set([window]);
    let parent = window.get_transient_for();
    for (let depth = 0; parent && depth < 8 && !seen.has(parent); depth++) {
        seen.add(parent);
        push(parent.get_wm_class());
        push(parent.get_gtk_application_id());
        parent = parent.get_transient_for();
    }
    return classes;
}

// The root class a window belongs to, for both the window-menu toggle and the
// D-Bus bridge: the last entry in the transient-for chain, so a dialog
// resolves to the app it belongs to rather than to its own (often different,
// sometimes absent) class.
function rootWindowClass(window) {
    const classes = windowClasses(window);
    return classes.length ? classes[classes.length - 1] : null;
}

// The same frame-type gate check_blur applies in Blur My Shell's
// components/applications.js (patched by patches/blur-my-shell-subwindows.patch
// to include ATTACHED and UTILITY too) — a window neither this nor Blur My
// Shell would ever blur is not offered up as something to blur.
function isBlurrable(frameType) {
    return frameType === Meta.FrameType.NORMAL ||
        frameType === Meta.FrameType.DIALOG ||
        frameType === Meta.FrameType.MODAL_DIALOG ||
        frameType === Meta.FrameType.ATTACHED ||
        frameType === Meta.FrameType.UTILITY;
}

const AuraGlassToggle = GObject.registerClass(
class AuraGlassToggle extends QuickSettings.QuickToggle {
    _init(extension) {
        super._init({
            title: _('Aura Glass'),
            iconName: 'preferences-desktop-display-symbolic',
            toggleMode: true,
        });
        this._extension = extension;
        this.connect('clicked', () => this._extension._toggleGlassMode());
    }
});

const AuraGlassIndicator = GObject.registerClass(
class AuraGlassIndicator extends QuickSettings.SystemIndicator {
    _init(extension) {
        super._init();
        this._toggle = new AuraGlassToggle(extension);
        this.quickSettingsItems.push(this._toggle);
    }

    get toggle() {
        return this._toggle;
    }
});

export default class AuraGlassBlurExtension extends Extension {
    enable() {
        this._settings = this._openBmsApplicationsSettings();
        if (this._settings) {
            this._origBuildMenu = WindowMenu.prototype._buildMenu;
            const self = this;
            WindowMenu.prototype._buildMenu = function (window) {
                self._origBuildMenu.call(this, window);
                self._appendBlurToggle(this, window);
            };
        }

        this._dbusImpl = Gio.DBusExportedObject.wrapJSObject(DBUS_IFACE, this);
        this._dbusImpl.export(Gio.DBus.session, DBUS_PATH);
        this._nameOwnerId = Gio.bus_own_name(
            Gio.BusType.SESSION, DBUS_NAME, Gio.BusNameOwnerFlags.NONE,
            null, null, null);

        // Lazy window tracking state: initialized empty, activated only on demand
        this._windowsChangedTimer = 0;
        this._trackingExpiryTimer = 0;
        this._windowCreatedId = 0;
        this._destroyIds = new Map();

        // Inhibit state tracking for power saving (battery, fullscreen, screen lock)
        this._inhibitReasons = new Set();
        this._initInhibitWatchers();

        // Pause blur effects on minimized windows
        this._initMinimizationWatcher();

        // Native icon synchronization following light/dark preference
        this._initIconSync();

        // Native automatic battery power saving (Auto-Eco Watcher)
        this._initAutoEcoWatcher();

        // Native monitor layout watch for Blur My Shell panel blur actor rebuild
        this._panelBlurTimer = 0;
        this._panelBlurRestoreTimer = 0;
        this._monitorsChangedId = Main.layoutManager.connect(
            'monitors-changed', () => this._schedulePanelBlurRebuild());
        this._schedulePanelBlurRebuild();

        // Native Quick Settings toggle tile
        this._initQuickSettings();

        // Background wallpaper auto-sync for GDM
        this._initGdmWallpaperWatcher();
    }

    disable() {
        if (this._origBuildMenu) {
            WindowMenu.prototype._buildMenu = this._origBuildMenu;
            this._origBuildMenu = null;
        }
        this._settings = null;

        this._destroyQuickSettings();
        this._destroyGdmWallpaperWatcher();
        this._destroyInhibitWatchers();
        this._destroyMinimizationWatcher();
        this._destroyIconSync();
        this._destroyAutoEcoWatcher();

        this._stopWindowTracking();
        this._destroyIds = null;

        if (this._monitorsChangedId) {
            Main.layoutManager.disconnect(this._monitorsChangedId);
            this._monitorsChangedId = 0;
        }
        if (this._panelBlurTimer) {
            GLib.source_remove(this._panelBlurTimer);
            this._panelBlurTimer = 0;
        }
        if (this._panelBlurRestoreTimer) {
            GLib.source_remove(this._panelBlurRestoreTimer);
            this._panelBlurRestoreTimer = 0;
        }

        if (this._nameOwnerId) {
            Gio.bus_unown_name(this._nameOwnerId);
            this._nameOwnerId = 0;
        }
        if (this._dbusImpl) {
            this._dbusImpl.unexport();
            this._dbusImpl = null;
        }
        _regexCache.clear();
    }

    // Native panel blur rebuild on monitor layout changes: Blur My Shell clips its
    // panel actor against monitor geometry, which is in flux at login and monitor
    // plug/unplug. Rebuilds the actor once settled (3s) without external daemons.
    _schedulePanelBlurRebuild() {
        this._checkLidState();
        if (this._panelBlurTimer) {
            GLib.source_remove(this._panelBlurTimer);
            this._panelBlurTimer = 0;
        }
        if (this._panelBlurRestoreTimer) {
            GLib.source_remove(this._panelBlurRestoreTimer);
            this._panelBlurRestoreTimer = 0;
        }

        this._panelBlurTimer = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, 3, () => {
                this._panelBlurTimer = 0;
                const panelSettings = this._openBmsSettings(BMS_PANEL_SCHEMA_ID);
                if (!panelSettings || !panelSettings.get_boolean('blur'))
                    return GLib.SOURCE_REMOVE;

                panelSettings.set_boolean('blur', false);
                this._panelBlurRestoreTimer = GLib.timeout_add(
                    GLib.PRIORITY_DEFAULT, 200, () => {
                        this._panelBlurRestoreTimer = 0;
                        const s = this._openBmsSettings(BMS_PANEL_SCHEMA_ID);
                        if (s)
                            s.set_boolean('blur', true);
                        return GLib.SOURCE_REMOVE;
                    });
                return GLib.SOURCE_REMOVE;
            });
    }

    // Blur My Shell ships its own compiled schemas rather than a system one,
    // under whichever of these two directories install_bms in
    // lib/steps-extensions.sh put it in — $HOME for the git build this
    // project does by default, /usr/share when a distro package supplied it
    // instead.
    _openBmsSettings(schemaId) {
        const dirs = [
            GLib.build_filenamev([GLib.get_user_data_dir(), 'gnome-shell',
                'extensions', BMS_UUID, 'schemas']),
            `/usr/share/gnome-shell/extensions/${BMS_UUID}/schemas`,
        ];
        const defaultSource = Gio.SettingsSchemaSource.get_default();
        for (const dir of dirs) {
            if (!GLib.file_test(dir, GLib.FileTest.IS_DIR))
                continue;
            let source;
            try {
                source = Gio.SettingsSchemaSource.new_from_directory(
                    dir, defaultSource, false);
            } catch (e) {
                continue;
            }
            const schema = source.lookup(schemaId, true);
            if (schema)
                return new Gio.Settings({settings_schema: schema});
        }
        return null;
    }

    _openBmsApplicationsSettings() {
        return this._openBmsSettings(BMS_SCHEMA_ID);
    }

    _appendBlurToggle(menu, window) {
        if (!isBlurrable(window.get_frame_type()))
            return;

        const classes = windowClasses(window);
        if (classes.length === 0)
            return;

        if (!this._settings.get_boolean('blur'))
            return;

        // The class this toggle writes into the lists: the rootmost entry in
        // the chain, so right-clicking a dialog toggles the app it belongs
        // to rather than adding the dialog's own (often different, and for
        // some clients absent) class as a new, unrelated entry.
        const wmClass = classes[classes.length - 1];

        // Above Close rather than after it. _buildMenu ends every menu with
        // its own separator then Close, so appending — which is what
        // menu.addAction/addMenuItem do with no position — puts this below
        // Close, one slot from where a click aimed at Close lands instead.
        // The insertion point is found rather than hardcoded to a fixed
        // index: this runs after the real _buildMenu, whose item count
        // varies with the window (a fixed window has no "Restore", a
        // single-workspace session has no "Move to Workspace" items), so the
        // last separator is always the one in front of Close regardless of
        // how many items came before it.
        const items = menu._getMenuItems();
        let closeSeparatorAt = -1;
        for (let i = items.length - 1; i >= 0; i--) {
            if (items[i] instanceof PopupMenu.PopupSeparatorMenuItem) {
                closeSeparatorAt = i;
                break;
            }
        }
        // No separator found at all is a menu shape this has never seen —
        // append rather than guess wrong and land the toggle mid-menu.
        const at = closeSeparatorAt >= 0 ? closeSeparatorAt : items.length;

        const separator = new PopupMenu.PopupSeparatorMenuItem();
        menu.addMenuItem(separator, at);

        // Built by hand rather than through menu.addAction: that override
        // (below) forces Ornament.NONE on every item it creates, and
        // addAction also takes no position argument to insert at.
        const item = new PopupMenu.PopupMenuItem(_('Blur This App'));
        menu.addMenuItem(item, at + 1);

        // Case-insensitive and over the whole chain: a dialog whose own
        // class differs from its parent's is still this app's own window.
        const isSelf = classes.some(
            c => c.toLowerCase() === SELF_WM_CLASS.toLowerCase());
        if (isSelf) {
            // A remove/uncheck here would only undo itself at the next
            // install.sh run — see app_blur_pin_allow.
            item.setOrnament(PopupMenu.Ornament.CHECK);
            item.setSensitive(false);
        } else {
            // enable-all decides which of the two lists is actually consulted
            // right now (apply_app_blur writes both every run regardless) —
            // see the comment above that function in lib/steps-dconf.sh. The
            // checkbox reads the one list scope currently consults, because
            // that is what answers "is this app blurred right now";
            // _toggleBlur below writes both, because "Blur This App" is one
            // choice and a scope flip made later in the settings window
            // should not silently reverse it. Coverage is tested over the
            // whole chain, so a dialog shows checked when the app it belongs
            // to is blurred, matching what check_blur itself now does in
            // Blur My Shell.
            const scope = this._settings.get_boolean('enable-all') ? 'all' : 'gtk';
            const key = scope === 'all' ? 'blacklist' : 'whitelist';
            const covered = matchesAnyClass(this._settings.get_strv(key), classes);
            const checked = scope === 'all' ? !covered : covered;

            item.setOrnament(checked ? PopupMenu.Ornament.CHECK
                                      : PopupMenu.Ornament.NONE);
            item.connect('activate', () => {
                this._toggleBlur(wmClass, !checked);
            });
        }
    }

    _toggleBlur(wmClass, wantBlurred) {
        // Both lists move together, unlike an edit made in the settings
        // window's per-app blur manager: this toggle is one checkbox with
        // one meaning, and apply_app_blur writes both memos every run
        // regardless of scope — see the comment above that function in
        // lib/steps-dconf.sh — so a choice recorded in only one of them is a
        // choice a later scope flip in the settings window would silently
        // undo. wantBlurred present in the allow list and absent from the
        // block list is that choice, whichever list scope ends up consulting.
        const allow = this._setListMembership('whitelist', wmClass, wantBlurred);
        const block = this._setListMembership('blacklist', wmClass, !wantBlurred);
        this._settings.set_strv('whitelist', allow);
        this._settings.set_strv('blacklist', block);
        this._writeMemo('app-blur-allow', allow);
        this._writeMemo('app-blur-block', block);
    }

    _setListMembership(key, wmClass, present) {
        const list = this._settings.get_strv(key);
        if (present) {
            if (matchesAny(list, wmClass))
                return list;
            return [...list, wmClass];
        }

        const removed = list.filter(p => wildcardToRegex(p).test(wmClass));
        if (removed.length === 0)
            return list;
        // A wildcard removed here can cover more than the one window that
        // was right-clicked — *chrome* also stops matching every other
        // window that trips it. Silently dropping it would make the block
        // list shrink for reasons the settings window never shows.
        if (removed.some(p => p !== wmClass)) {
            const listLabel = key === 'blacklist'
                ? _('the never-blur list') : _('the always-blur list');
            Main.notify('aura-glass',
                `${_('Removed from')} ${listLabel}: ${removed.join(', ')}`);
        }
        return list.filter(p => !removed.includes(p));
    }

    // Shipped as memos rather than trusting dconf alone, for the same reason
    // apply_app_blur writes both: a user's edited list has to survive the
    // next ./install.sh, and app_blur_lines prefers the memo over whatever
    // is already in dconf.
    _writeMemo(name, list) {
        const dir = GLib.build_filenamev([GLib.get_user_config_dir(), 'aura-glass']);
        GLib.mkdir_with_parents(dir, 0o755);
        const path = GLib.build_filenamev([dir, name]);
        const contents = list.length ? `${list.join('\n')}\n` : '';
        GLib.file_set_contents(path, contents);
    }

    // ---- D-Bus bridge ------------------------------------------------------
    //
    // What the settings window's Per-app blur page cannot otherwise find out:
    // what windows exist right now (ListWindows, for "Open now"). It answers in
    // terms of the same root wm_class the toggle above writes, so a row here and
    // a row on that page are asking about the same thing.

    // wm_class, display name, and how many open windows share it — a browser
    // with six tabs across three windows is one row, not three, because the
    // switch on that row is one choice about the class, not about any one of
    // its windows.
    ListWindows() {
        this._ensureWindowTracking();
        const tracker = Shell.WindowTracker.get_default();
        const groups = new Map();
        for (const actor of global.get_window_actors()) {
            const window = actor.get_meta_window();
            if (!window || window.is_override_redirect())
                continue;
            if (!isBlurrable(window.get_frame_type()))
                continue;
            if (window.is_skip_taskbar())
                continue;
            const wmClass = rootWindowClass(window);
            if (!wmClass)
                continue;

            let entry = groups.get(wmClass);
            if (!entry) {
                let name = wmClass;
                const app = tracker.get_window_app(window);
                if (app)
                    name = app.get_name();
                else if (window.get_title())
                    name = window.get_title();
                entry = {name, count: 0};
                groups.set(wmClass, entry);
            }
            entry.count += 1;
        }
        return [...groups.entries()].map(
            ([wmClass, {name, count}]) => [wmClass, name, count]);
    }

    // ---- lazy window tracking & keeping ListWindows fresh --------------------

    // Windows are tracked only on demand when a client (e.g. the settings window)
    // calls ListWindows. Disconnects automatically after 30 seconds of inactivity
    // to avoid idle CPU wakeups and D-Bus traffic during ordinary desktop use.
    _ensureWindowTracking() {
        if (this._trackingExpiryTimer) {
            GLib.source_remove(this._trackingExpiryTimer);
            this._trackingExpiryTimer = 0;
        }
        this._trackingExpiryTimer = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, 30, () => {
                this._trackingExpiryTimer = 0;
                this._stopWindowTracking();
                return GLib.SOURCE_REMOVE;
            });

        if (this._windowCreatedId)
            return;

        this._windowCreatedId = global.display.connect(
            'window-created', (_display, window) => this._trackWindow(window));

        for (const actor of global.get_window_actors())
            this._trackWindow(actor.get_meta_window());
    }

    _stopWindowTracking() {
        if (this._trackingExpiryTimer) {
            GLib.source_remove(this._trackingExpiryTimer);
            this._trackingExpiryTimer = 0;
        }
        if (this._windowsChangedTimer) {
            GLib.source_remove(this._windowsChangedTimer);
            this._windowsChangedTimer = 0;
        }
        if (this._windowCreatedId) {
            global.display.disconnect(this._windowCreatedId);
            this._windowCreatedId = 0;
        }
        if (this._destroyIds) {
            for (const [window, id] of this._destroyIds)
                window.disconnect(id);
            this._destroyIds.clear();
        }
    }

    _trackWindow(window) {
        if (!window || this._destroyIds.has(window))
            return;
        // Skip unblurrable, override-redirect or transient OS window actors
        if (window.is_override_redirect() || window.is_skip_taskbar() || !isBlurrable(window.get_frame_type()))
            return;

        const id = window.connect('unmanaged', () => {
            this._destroyIds.delete(window);
            this._scheduleWindowsChanged();
        });
        this._destroyIds.set(window, id);
        this._scheduleWindowsChanged();
    }

    // Debounced: a window opening or closing is rarely one event by itself —
    // a browser launch is a splash window replaced by the real one moments
    // later — and firing once per intermediate window would have the
    // settings window's list flicker rather than settle.
    _scheduleWindowsChanged() {
        if (!this._windowCreatedId)
            return;

        if (this._windowsChangedTimer)
            GLib.source_remove(this._windowsChangedTimer);
        this._windowsChangedTimer = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT, 300, () => {
                this._windowsChangedTimer = 0;
                if (this._dbusImpl)
                    this._dbusImpl.emit_signal('WindowsChanged', null);
                return GLib.SOURCE_REMOVE;
            });
    }

    // ---- native icon synchronization --------------------------------------

    // Keeps the icon theme aligned with the light/dark preference without
    // needing external background daemons.
    _initIconSync() {
        try {
            this._interfaceSettings = new Gio.Settings({
                schema_id: 'org.gnome.desktop.interface',
            });
            this._colorSchemeChangedId = this._interfaceSettings.connect(
                'changed::color-scheme', () => this._syncIconTheme());
            this._syncIconTheme();
        } catch (_) {
            this._interfaceSettings = null;
        }
    }

    _destroyIconSync() {
        if (this._colorSchemeChangedId && this._interfaceSettings) {
            this._interfaceSettings.disconnect(this._colorSchemeChangedId);
            this._colorSchemeChangedId = 0;
        }
        this._interfaceSettings = null;
    }

    _getIconBaseName() {
        if (this._cachedIconBase)
            return this._cachedIconBase;

        const confDir = GLib.build_filenamev([GLib.get_user_config_dir(), 'aura-glass']);
        const packFile = GLib.build_filenamev([confDir, 'icon-pack']);
        if (GLib.file_test(packFile, GLib.FileTest.EXISTS)) {
            try {
                const [ok, bytes] = GLib.file_get_contents(packFile);
                if (ok) {
                    const pack = new TextDecoder().decode(bytes).trim();
                    if (pack === 'keep') {
                        this._cachedIconBase = 'keep';
                        return 'keep';
                    }
                }
            } catch (_) {}
        }

        let base = 'Colloid';
        const iconsFile = GLib.build_filenamev([confDir, 'icons']);
        const tahoeFile = GLib.build_filenamev([GLib.get_user_config_dir(), 'tahoe-glass', 'icons']);
        for (const f of [iconsFile, tahoeFile]) {
            if (GLib.file_test(f, GLib.FileTest.EXISTS)) {
                try {
                    const [ok, bytes] = GLib.file_get_contents(f);
                    if (ok) {
                        const name = new TextDecoder().decode(bytes).trim();
                        if (name) {
                            base = name;
                            break;
                        }
                    }
                } catch (_) {}
            }
        }
        this._cachedIconBase = base;
        return base;
    }

    _syncIconTheme() {
        if (!this._interfaceSettings)
            return;

        const base = this._getIconBaseName();
        if (base === 'keep')
            return;

        const scheme = this._interfaceSettings.get_string('color-scheme') || '';
        const variant = scheme.includes('prefer-dark') ? 'Dark' : 'Light';

        const candidates = [
            `${base}-${variant}`,
            `${base}-${variant.toLowerCase()}`,
            base,
        ];

        let want = null;
        for (const c of candidates) {
            const userDir = GLib.build_filenamev([GLib.get_home_dir(), '.local', 'share', 'icons', c]);
            const sysDir = `/usr/share/icons/${c}`;
            if (GLib.file_test(userDir, GLib.FileTest.IS_DIR) || GLib.file_test(sysDir, GLib.FileTest.IS_DIR)) {
                want = c;
                break;
            }
        }

        if (!want)
            return;

        const cur = this._interfaceSettings.get_string('icon-theme');
        if (cur !== want)
            this._interfaceSettings.set_string('icon-theme', want);
    }

    // ---- Performance Watchers: Fullscreen & Screen Lock Inhibit ------------

    _initInhibitWatchers() {
        this._fullscreenSignalId = 0;
        this._lockedSignalId = 0;

        try {
            if (global.display) {
                this._fullscreenSignalId = global.display.connect(
                    'in-fullscreen-changed', () => this._checkFullscreen());
            }
        } catch (_) {}

        try {
            if (Main.screenShield) {
                this._lockedSignalId = Main.screenShield.connect(
                    'locked-changed', () => this._checkLocked());
            }
        } catch (_) {}

        this._checkFullscreen();
        this._checkLocked();
    }

    _destroyInhibitWatchers() {
        if (this._fullscreenSignalId && global.display) {
            global.display.disconnect(this._fullscreenSignalId);
            this._fullscreenSignalId = 0;
        }
        if (this._lockedSignalId && Main.screenShield) {
            Main.screenShield.disconnect(this._lockedSignalId);
            this._lockedSignalId = 0;
        }
        if (this._inhibitReasons)
            this._inhibitReasons.clear();
    }

    _checkFullscreen() {
        let isFullscreen = false;
        try {
            for (const actor of global.get_window_actors()) {
                const w = actor.get_meta_window();
                if (w && !w.is_override_redirect() && w.is_fullscreen()) {
                    isFullscreen = true;
                    break;
                }
            }
        } catch (_) {}

        if (isFullscreen)
            this._addInhibitReason('fullscreen', false);
        else
            this._removeInhibitReason('fullscreen', false);
    }

    _checkLocked() {
        if (!Main.screenShield)
            return;
        if (Main.screenShield.locked) {
            this._addInhibitReason('locked', false);
            if (typeof gc === 'function') {
                try { gc(); } catch (_) {}
            }
        } else {
            this._removeInhibitReason('locked', false);
        }
    }

    _addInhibitReason(reason, isInitial) {
        if (!this._inhibitReasons)
            return;

        const wasEmpty = (this._inhibitReasons.size === 0);
        this._inhibitReasons.add(reason);

        if (wasEmpty) {
            const confDir = GLib.build_filenamev([GLib.get_user_config_dir(), 'aura-glass']);
            const appSettings = this._openBmsSettings(BMS_SCHEMA_ID);
            if (appSettings && appSettings.get_boolean('blur')) {
                appSettings.set_boolean('blur', false);
                const activeMarker = GLib.build_filenamev([confDir, 'perf-inhibited']);
                GLib.file_set_contents(activeMarker, '1\n');
            }
            if (!isInitial && reason === 'battery') {
                Main.notify('Aura Glass', _('Eco mode enabled (running on battery)'));
            }
        }
    }

    _removeInhibitReason(reason, isInitial) {
        if (!this._inhibitReasons)
            return;

        this._inhibitReasons.delete(reason);
        if (this._inhibitReasons.size === 0) {
            const confDir = GLib.build_filenamev([GLib.get_user_config_dir(), 'aura-glass']);
            const activeMarker = GLib.build_filenamev([confDir, 'perf-inhibited']);
            const autoEcoMarker = GLib.build_filenamev([confDir, 'auto-eco-active']);
            const stylingOff = GLib.build_filenamev([confDir, 'styling-off']);
            const appSettings = this._openBmsSettings(BMS_SCHEMA_ID);

            if (GLib.file_test(activeMarker, GLib.FileTest.EXISTS) || GLib.file_test(autoEcoMarker, GLib.FileTest.EXISTS)) {
                try { GLib.unlink(activeMarker); } catch (_) {}
                try { GLib.unlink(autoEcoMarker); } catch (_) {}
                if (appSettings && !GLib.file_test(stylingOff, GLib.FileTest.EXISTS))
                    appSettings.set_boolean('blur', true);
            }
            if (!isInitial && reason === 'battery') {
                Main.notify('Aura Glass', _('Full frosted glass restored (AC plugged in)'));
            }
        }
    }

    // ---- native auto-eco battery watcher -----------------------------------

    // Monitors UPower for battery/AC transitions. On battery, automatically
    // pauses window blur and lowers hacks-level to 1 (clipped redraws).
    // Restores full frosted glass when plugged back into AC.
    _initAutoEcoWatcher() {
        this._upowerProxy = null;
        this._upowerSignalId = 0;
        this._autoEcoActive = false;

        try {
            this._upowerProxy = Gio.DBusProxy.new_for_bus_sync(
                Gio.BusType.SYSTEM,
                Gio.DBusProxyFlags.NONE,
                null,
                'org.freedesktop.UPower',
                '/org/freedesktop/UPower',
                'org.freedesktop.UPower',
                null
            );

            this._upowerSignalId = this._upowerProxy.connect(
                'g-properties-changed',
                (_proxy, changed) => {
                    const onBatVal = changed.lookup_value('OnBattery', null);
                    if (onBatVal !== null)
                        this._onPowerChanged(onBatVal.unpack(), false);

                    const lidVal = changed.lookup_value('LidIsClosed', null);
                    if (lidVal !== null)
                        this._onLidChanged(lidVal.unpack());
                }
            );

            const onBatProp = this._upowerProxy.get_cached_property('OnBattery');
            if (onBatProp !== null)
                this._onPowerChanged(onBatProp.unpack(), true);

            const lidProp = this._upowerProxy.get_cached_property('LidIsClosed');
            if (lidProp !== null)
                this._onLidChanged(lidProp.unpack());
        } catch (_) {
            this._upowerProxy = null;
        }
    }

    _destroyAutoEcoWatcher() {
        if (this._upowerSignalId && this._upowerProxy) {
            this._upowerProxy.disconnect(this._upowerSignalId);
            this._upowerSignalId = 0;
        }
        this._upowerProxy = null;
    }

    _onPowerChanged(onBattery, isInitial) {
        const confDir = GLib.build_filenamev([GLib.get_user_config_dir(), 'aura-glass']);
        const optOut = GLib.build_filenamev([confDir, 'no-auto-eco']);
        if (GLib.file_test(optOut, GLib.FileTest.EXISTS))
            return;

        const coreSettings = this._openBmsSettings(BMS_CORE_SCHEMA_ID);

        if (onBattery) {
            if (this._autoEcoActive)
                return;
            this._autoEcoActive = true;

            // Reduce redraw cost: clipped redraws on (hacks-level=1)
            if (coreSettings) {
                try { coreSettings.set_int('hacks-level', 1); } catch (_) {
                    try { coreSettings.set_enum('hacks-level', 1); } catch (_) {}
                }
            }

            this._addInhibitReason('battery', isInitial);
        } else {
            if (!this._autoEcoActive && !isInitial)
                return;
            this._autoEcoActive = false;

            // Restore full-screen repaints for smooth frosted overview
            if (coreSettings) {
                try { coreSettings.set_int('hacks-level', 2); } catch (_) {
                    try { coreSettings.set_enum('hacks-level', 2); } catch (_) {}
                }
            }

            this._removeInhibitReason('battery', isInitial);
        }
    }

    _onLidChanged(isClosed) {
        const monitors = Main.layoutManager?.monitors || [];
        const hasExternal = monitors.length > 1;
        if (isClosed && !hasExternal)
            this._addInhibitReason('lid-closed', false);
        else
            this._removeInhibitReason('lid-closed', false);
    }

    _checkLidState() {
        if (!this._upowerProxy)
            return;
        const lidProp = this._upowerProxy.get_cached_property('LidIsClosed');
        if (lidProp !== null)
            this._onLidChanged(lidProp.unpack());
    }

    // ---- Minimized Window Blur Shader Suspension ---------------------------

    _initMinimizationWatcher() {
        this._minWindowCreatedId = 0;
        this._minSignals = new Map();

        if (global.display) {
            this._minWindowCreatedId = global.display.connect(
                'window-created', (_d, window) => this._trackMinimization(window));
        }

        for (const actor of global.get_window_actors()) {
            const w = actor.get_meta_window();
            if (w)
                this._trackMinimization(w);
        }
    }

    _destroyMinimizationWatcher() {
        if (this._minWindowCreatedId && global.display) {
            global.display.disconnect(this._minWindowCreatedId);
            this._minWindowCreatedId = 0;
        }
        if (this._minSignals) {
            for (const [window, ids] of this._minSignals) {
                for (const id of ids)
                    window.disconnect(id);
            }
            this._minSignals.clear();
            this._minSignals = null;
        }
    }

    _trackMinimization(window) {
        if (!window || !this._minSignals || this._minSignals.has(window) || window.is_override_redirect())
            return;

        const unmanagedId = window.connect('unmanaged', () => {
            this._untrackMinimization(window);
        });

        const notifyMinId = window.connect('notify::minimized', () => {
            this._updateWindowBlur(window);
        });

        this._minSignals.set(window, [unmanagedId, notifyMinId]);
        this._updateWindowBlur(window);
    }

    _untrackMinimization(window) {
        if (!this._minSignals)
            return;
        const ids = this._minSignals.get(window);
        if (ids) {
            for (const id of ids)
                window.disconnect(id);
            this._minSignals.delete(window);
        }
    }

    _updateWindowBlur(window) {
        if (!window)
            return;
        const isMinimized = window.minimized || (typeof window.is_hidden === 'function' && window.is_hidden());
        const blurActor = window.blur_actor;
        if (blurActor)
            blurActor.opacity = isMinimized ? 0 : 255;

        const pipeline = window.bg_manager?._bms_pipeline;
        if (pipeline) {
            if (pipeline.effect)
                pipeline.effect.set_enabled(!isMinimized);
            pipeline.effects?.forEach(effect => effect.set_enabled(!isMinimized));
        }
    }

    // ---- Quick Settings Toggle & Menu Tile ---------------------------------

    _initQuickSettings() {
        this._quickIndicator = null;
        this._qsMenuStateId = 0;

        try {
            const quickSettings = Main.panel?.statusArea?.quickSettings;
            if (!quickSettings)
                return;

            this._quickIndicator = new AuraGlassIndicator(this);
            quickSettings.addExternalIndicator(this._quickIndicator);

            if (quickSettings.menu) {
                this._qsMenuStateId = quickSettings.menu.connect(
                    'open-state-changed', (_m, open) => {
                        if (open)
                            this._syncQuickToggle();
                    }
                );
            }
            this._syncQuickToggle();
        } catch (_) {
            this._quickIndicator = null;
        }
    }

    _destroyQuickSettings() {
        if (this._qsMenuStateId && Main.panel?.statusArea?.quickSettings?.menu) {
            Main.panel.statusArea.quickSettings.menu.disconnect(this._qsMenuStateId);
            this._qsMenuStateId = 0;
        }
        if (this._quickIndicator) {
            try { this._quickIndicator.destroy(); } catch (_) {}
            this._quickIndicator = null;
        }
    }

    _toggleGlassMode() {
        try {
            const proc = Gio.Subprocess.new(
                ['aura-glass-mode', 'toggle', '--notify'],
                Gio.SubprocessFlags.NONE
            );
            proc.wait_async(null, () => this._syncQuickToggle());
        } catch (_) {
            const confDir = GLib.build_filenamev([GLib.get_user_config_dir(), 'aura-glass']);
            const stylingOff = GLib.build_filenamev([confDir, 'styling-off']);
            const appSettings = this._openBmsSettings(BMS_SCHEMA_ID);
            if (GLib.file_test(stylingOff, GLib.FileTest.EXISTS)) {
                try { GLib.unlink(stylingOff); } catch (_) {}
                if (appSettings)
                    appSettings.set_boolean('blur', true);
            } else {
                GLib.file_set_contents(stylingOff, '1\n');
                if (appSettings)
                    appSettings.set_boolean('blur', false);
            }
            this._syncQuickToggle();
        }
    }

    _syncQuickToggle() {
        if (!this._quickIndicator || !this._quickIndicator.toggle)
            return;

        const confDir = GLib.build_filenamev([GLib.get_user_config_dir(), 'aura-glass']);
        const stylingOff = GLib.build_filenamev([confDir, 'styling-off']);
        const modeFile = GLib.build_filenamev([confDir, 'glass-mode']);

        let mode = 'frosted';
        if (GLib.file_test(stylingOff, GLib.FileTest.EXISTS)) {
            mode = 'solid';
        } else if (GLib.file_test(modeFile, GLib.FileTest.EXISTS)) {
            try {
                const [ok, bytes] = GLib.file_get_contents(modeFile);
                if (ok) {
                    const m = new TextDecoder().decode(bytes).trim();
                    if (m === 'frosted' || m === 'transparent' || m === 'solid')
                        mode = m;
                }
            } catch (_) {}
        }

        const toggle = this._quickIndicator.toggle;
        if (mode === 'solid') {
            toggle.checked = false;
            toggle.subtitle = _('Solid');
        } else if (mode === 'transparent') {
            toggle.checked = true;
            toggle.subtitle = _('Transparent');
        } else {
            toggle.checked = true;
            toggle.subtitle = _('Frosted');
        }
    }

    // ---- Automatic GDM Lockscreen Wallpaper Sync ---------------------------

    _initGdmWallpaperWatcher() {
        this._bgSettings = null;
        this._bgChangedId = 0;
        this._bgDarkChangedId = 0;
        this._gdmSyncTimer = 0;

        const hasGdm = GLib.find_program_in_path('gdm') ||
                       GLib.find_program_in_path('gdm3') ||
                       GLib.file_test('/usr/sbin/gdm3', GLib.FileTest.EXISTS);
        if (!hasGdm)
            return;

        try {
            this._bgSettings = new Gio.Settings({
                schema_id: 'org.gnome.desktop.background',
            });
            this._bgChangedId = this._bgSettings.connect('changed::picture-uri', () => {
                this._scheduleGdmSync();
            });
            this._bgDarkChangedId = this._bgSettings.connect('changed::picture-uri-dark', () => {
                this._scheduleGdmSync();
            });
        } catch (_) {
            this._bgSettings = null;
        }
    }

    _scheduleGdmSync() {
        if (this._gdmSyncTimer)
            GLib.source_remove(this._gdmSyncTimer);

        this._gdmSyncTimer = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, 4, () => {
                this._gdmSyncTimer = 0;
                try {
                    Gio.Subprocess.new(
                        ['aura-glass-gdm-sync'],
                        Gio.SubprocessFlags.NONE
                    );
                } catch (_) {}
                return GLib.SOURCE_REMOVE;
            });
    }

    _destroyGdmWallpaperWatcher() {
        if (this._gdmSyncTimer) {
            GLib.source_remove(this._gdmSyncTimer);
            this._gdmSyncTimer = 0;
        }
        if (this._bgChangedId && this._bgSettings) {
            this._bgSettings.disconnect(this._bgChangedId);
            this._bgChangedId = 0;
        }
        if (this._bgDarkChangedId && this._bgSettings) {
            this._bgSettings.disconnect(this._bgDarkChangedId);
            this._bgDarkChangedId = 0;
        }
        this._bgSettings = null;
    }
}
