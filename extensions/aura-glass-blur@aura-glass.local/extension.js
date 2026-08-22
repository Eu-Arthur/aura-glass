/* aura-glass window-menu blur toggle
 *
 * The per-app blur allow/block list Blur My Shell reads is otherwise editable
 * in exactly two places: --app-blur-allow/--app-blur-block on install.sh, and
 * the AppListWindow in the aura-glass settings window. Both mean leaving the
 * window you actually want to toggle. This puts the same question where it
 * gets asked — right-click the titlebar, "Blur This App" — by monkeypatching
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
 */

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {WindowMenu} from 'resource:///org/gnome/shell/ui/windowMenu.js';
import {Extension, gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';

const BMS_UUID = 'blur-my-shell@aunetx';
const BMS_SCHEMA_ID = 'org.gnome.shell.extensions.blur-my-shell.applications';

// Pinned back onto the whitelist by every install.sh run (app_blur_pin_allow
// in lib/steps-dconf.sh) — the same string is duplicated in
// gui/aura_glass_settings.py (SELF_WM_CLASS) and checked against this one by
// tools/check-app-blur-lists.sh.
const SELF_WM_CLASS = 'io.github.DevWebeloper.AuraGlassSettings';

// Mirrors Blur My Shell's own components/applications.js wildcardToRegex:
// escape every regex metacharacter except * and ?, anchor at both ends,
// * -> .*, ? -> ., case-insensitive. Brackets are escaped rather than left to
// form a character class, so [abc] matches the three literal characters —
// this has to agree with that function exactly, or this toggle and the
// allow/block list in the settings window would disagree about what a
// pattern covers. lib/steps-dconf.sh (app_blur_covers_self) and
// gui/aura_glass_settings.py (pattern_matches) are the other two mirrors.
function wildcardToRegex(pattern) {
    const escaped = pattern
        .replace(/[.+^${}()|[\]\\]/g, '\\$&')
        .replace(/\*/g, '.*')
        .replace(/\?/g, '.');
    return new RegExp(`^${escaped}$`, 'i');
}

function matchesAny(patterns, wmClass) {
    return patterns.some(p => p.trim() !== '' && wildcardToRegex(p).test(wmClass));
}

export default class AuraGlassBlurExtension extends Extension {
    enable() {
        this._settings = this._openBmsApplicationsSettings();
        if (!this._settings)
            return;

        this._origBuildMenu = WindowMenu.prototype._buildMenu;
        const self = this;
        WindowMenu.prototype._buildMenu = function (window) {
            self._origBuildMenu.call(this, window);
            self._appendBlurToggle(this, window);
        };
    }

    disable() {
        if (this._origBuildMenu) {
            WindowMenu.prototype._buildMenu = this._origBuildMenu;
            this._origBuildMenu = null;
        }
        this._settings = null;
    }

    // Blur My Shell ships its own compiled schema rather than a system one,
    // under whichever of these two directories install_bms in
    // lib/steps-extensions.sh put it in — $HOME for the git build this
    // project does by default, /usr/share when a distro package supplied it
    // instead (ext_supports_shell checks the same two places). `trusted:
    // false` is exactly what GNOME Shell's own Extension.getSettings() passes
    // for a schema living in an extension's own directory.
    _openBmsApplicationsSettings() {
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
            const schema = source.lookup(BMS_SCHEMA_ID, true);
            if (schema)
                return new Gio.Settings({settings_schema: schema});
        }
        return null;
    }

    _appendBlurToggle(menu, window) {
        // The same frame-type gate check_blur applies in Blur My Shell's
        // components/applications.js — a window this never blurs gets no
        // item offering to toggle it.
        const frameType = window.get_frame_type();
        if (frameType !== Meta.FrameType.NORMAL &&
            frameType !== Meta.FrameType.DIALOG &&
            frameType !== Meta.FrameType.MODAL_DIALOG)
            return;

        const wmClass = window.get_wm_class();
        if (!wmClass)
            return;

        if (!this._settings.get_boolean('blur'))
            return;

        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        if (wmClass === SELF_WM_CLASS) {
            // A remove/uncheck here would only undo itself at the next
            // install.sh run — see app_blur_pin_allow.
            const pinned = menu.addAction(_('Blur This App'), () => {});
            pinned.setOrnament(PopupMenu.Ornament.CHECK);
            pinned.setSensitive(false);
            return;
        }

        // enable-all decides which list is actually consulted (apply_app_blur
        // writes both every run regardless) — see the comment above that
        // function in lib/steps-dconf.sh. "Blur This App" always means the
        // same thing either way, so which list gets edited, and whether
        // membership means on or off, flips with it.
        const scope = this._settings.get_boolean('enable-all') ? 'all' : 'gtk';
        const key = scope === 'all' ? 'blacklist' : 'whitelist';
        const covered = matchesAny(this._settings.get_strv(key), wmClass);
        const checked = scope === 'all' ? !covered : covered;

        const item = menu.addAction(_('Blur This App'), () => {
            this._toggleBlur(scope, wmClass, !checked);
        });
        if (checked)
            item.setOrnament(PopupMenu.Ornament.CHECK);
    }

    _toggleBlur(scope, wmClass, wantBlurred) {
        // In gtk mode membership in the whitelist is what turns blur on; in
        // all mode membership in the blacklist is what turns it off. Both
        // reduce to "is wmClass present in `key`" with `present` flipped
        // between them.
        const key = scope === 'all' ? 'blacklist' : 'whitelist';
        const present = scope === 'all' ? !wantBlurred : wantBlurred;

        const list = this._setListMembership(key, wmClass, present);
        this._settings.set_strv(key, list);
        this._writeMemo(key === 'blacklist' ? 'app-blur-block' : 'app-blur-allow',
            list);
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
}
