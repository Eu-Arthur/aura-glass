# shellcheck shell=bash
# aura-glass — GDM login screen theme installation, wallpaper sync, and restoration.
#
# Unlike user themes which live under $HOME, GDM runs as a separate system user
# and loads its theme from /usr/share/gnome-shell/gnome-shell-theme.gresource.
# Modifying it requires root/sudo privileges.
#
# Sourced by install.sh and uninstall.sh.

WHITESUR_REPO="https://github.com/vinceliuice/WhiteSur-gtk-theme.git"
WHITESUR_REF="1912dee2e48d"
CONF_DIR="${CONF_DIR:-$HOME/.config/aura-glass}"

get_desktop_wallpaper() {
    local uri
    uri="$(gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null || true)"
    uri="${uri//\'/}"
    if [ -z "$uri" ] || [ "$uri" = "nothing" ] || [ "$uri" = "''" ]; then
        uri="$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || true)"
        uri="${uri//\'/}"
    fi
    if [[ "$uri" =~ ^file://(.*) ]]; then
        python3 -c "import urllib.parse, sys; print(urllib.parse.unquote(sys.argv[1][7:]))" "$uri" 2>/dev/null || echo "${uri#file://}"
    else
        echo "$uri"
    fi
}

resolve_gdm_wallpaper_source() {
    local preferred="${1:-default}"

    # 1. Check explicitly specified background (--gdm-background)
    if [ -n "$preferred" ] && [ "$preferred" != "default" ]; then
        if [ -f "$preferred" ]; then
            echo "$preferred"
            return 0
        else
            warn "specified GDM background not found: $preferred"
        fi
    fi

    # 2. Check active desktop wallpaper
    local cur; cur="$(get_desktop_wallpaper)"
    if [ -n "$cur" ] && [ -f "$cur" ]; then
        echo "$cur"
        return 0
    fi

    # 3. Check known distribution default wallpapers
    local distro_candidates=(
        "/usr/share/backgrounds/gnome/adwaita-d.jxl"
        "/usr/share/backgrounds/gnome/adwaita-l.jxl"
        "/usr/share/backgrounds/gnome/adwaita-d.webp"
        "/usr/share/backgrounds/gnome/adwaita-l.webp"
        "/usr/share/backgrounds/gnome/adwaita-d.jpg"
        "/usr/share/backgrounds/gnome/adwaita-l.jpg"
        "/usr/share/backgrounds/gnome/adwaita-d.png"
        "/usr/share/backgrounds/gnome/adwaita-l.png"
        "/usr/share/backgrounds/default.png"
        "/usr/share/backgrounds/default.jpg"
        "/usr/share/backgrounds/warty-final-ubuntu.png"
    )
    for f in "${distro_candidates[@]}"; do
        if [ -f "$f" ]; then
            echo "$f"
            return 0
        fi
    done

    # 4. Search any readable image in /usr/share/backgrounds
    local any_bg
    any_bg="$(find /usr/share/backgrounds -maxdepth 2 -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.webp" \) 2>/dev/null | head -n 1 || true)"
    if [ -n "$any_bg" ] && [ -f "$any_bg" ]; then
        echo "$any_bg"
        return 0
    fi

    # Fallback signal for procedural generator
    echo "procedural"
}

generate_gdm_wallpaper() {
    local src="$1" dst="$2"
    [ -n "$src" ] || src="procedural"

    local memo_file="$CONF_DIR/gdm-wallpaper-memo"
    local current_memo
    if [ "$src" != "procedural" ] && [ -f "$src" ]; then
        current_memo="$src:$(stat -c %Y "$src" 2>/dev/null || true)"
    else
        current_memo="procedural:aura-glass"
    fi

    if [ -f "$dst" ] && [ -s "$dst" ] && [ -f "$memo_file" ]; then
        if [ "$(read_memo "$memo_file")" = "$current_memo" ]; then
            return 0
        fi
    fi

    python3 - "$src" "$dst" <<'PY' || return 1
import os, sys, subprocess, xml.etree.ElementTree as ET

src = sys.argv[1]
dst = sys.argv[2]

def generate_procedural_fallback(out_path):
    from PIL import Image, ImageFilter, ImageDraw
    im = Image.new('RGB', (2560, 1440), color=(14, 16, 26))
    draw = ImageDraw.Draw(im)
    for y in range(1440):
        factor = y / 1440.0
        r = int(14 + factor * 14)
        g = int(17 + factor * 20)
        b = int(28 + factor * 42)
        draw.line([(0, y), (2560, y)], fill=(r, g, b))
    im = im.filter(ImageFilter.GaussianBlur(radius=5))
    im.save(out_path, format="PNG")

def resolve_source(path):
    if not path or path == "procedural" or not os.path.exists(path):
        return None
    if path.lower().endswith('.xml'):
        try:
            tree = ET.parse(path)
            root = tree.getroot()
            for file_elem in root.iter('file'):
                candidate = file_elem.text.strip() if file_elem.text else ""
                if candidate and os.path.exists(candidate):
                    return candidate
            for from_elem in root.iter('from'):
                candidate = from_elem.text.strip() if from_elem.text else ""
                if candidate and os.path.exists(candidate):
                    return candidate
        except Exception:
            return None
    return path

resolved = resolve_source(src)

try:
    from PIL import Image, ImageFilter, ImageEnhance, ImageOps
    if not resolved:
        generate_procedural_fallback(dst)
        sys.exit(0)

    if resolved.lower().endswith(('.svg', '.svgz')):
        try:
            subprocess.run([
                "magick", "-density", "150", resolved,
                "-resize", "2560x1440^", "-gravity", "center", "-extent", "2560x1440",
                "-blur", "0x30", "-fill", "black", "-colorize", "40%", dst
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            sys.exit(0)
        except Exception:
            pass

    im = Image.open(resolved).convert('RGB')
    small = ImageOps.fit(im, (640, 360), method=Image.Resampling.BILINEAR)
    small = small.filter(ImageFilter.BoxBlur(10))
    im = small.resize((2560, 1440), resample=Image.Resampling.BILINEAR)
    enhancer = ImageEnhance.Brightness(im)
    im = enhancer.enhance(0.55)
    im.save(dst, format="PNG")
    sys.exit(0)
except Exception:
    pass

# ImageMagick fallback
try:
    if resolved and os.path.exists(resolved):
        subprocess.run([
            "magick", resolved,
            "-resize", "2560x1440^", "-gravity", "center", "-extent", "2560x1440",
            "-blur", "0x30", "-fill", "black", "-colorize", "40%", dst
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        sys.exit(0)
    else:
        subprocess.run([
            "magick", "-size", "2560x1440", "gradient:#0e101a-#1c2342", dst
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        sys.exit(0)
except Exception:
    sys.exit(1)
PY

    mkdir -p "$CONF_DIR"
    printf '%s\n' "$current_memo" > "$memo_file" 2>/dev/null || true
    return 0
}

sync_gdm_monitors() {
    step "Syncing primary monitor to GDM login screen (requires sudo)"

    local user_monitors="$HOME/.config/monitors.xml"
    if [ ! -f "$user_monitors" ]; then
        warn "no ~/.config/monitors.xml found — monitor layout not configured in GNOME Settings"
        return 0
    fi

    local synced=0

    # 1. Global XDG config directory — standard for Mutter / GDM 40-50+ with systemd dynamic users
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: sudo mkdir -p /etc/xdg && sudo cp -f $user_monitors /etc/xdg/monitors.xml"
        synced=1
    else
        sudo mkdir -p /etc/xdg
        sudo cp -f "$user_monitors" /etc/xdg/monitors.xml
        sudo chown "$USER:" /etc/xdg/monitors.xml 2>/dev/null || true
        sudo chmod 644 /etc/xdg/monitors.xml
        synced=1
    fi

    # 2. GDM user home & seat0 directories for legacy/standard setups across distributions
    for gdm_dir in /var/lib/gdm /var/lib/gdm3; do
        if [ -d "$gdm_dir" ] || [ "$gdm_dir" = "/var/lib/gdm" ]; then
            if [ "${DRY_RUN:-0}" = 1 ]; then
                info "dry-run: sudo mkdir -p $gdm_dir/.config && sudo cp -f $user_monitors $gdm_dir/.config/monitors.xml"
                synced=1
            else
                sudo mkdir -p "$gdm_dir/.config"
                sudo cp -f "$user_monitors" "$gdm_dir/.config/monitors.xml"
                sudo chmod 755 "$gdm_dir/.config"
                sudo chown "$USER:" "$gdm_dir/.config/monitors.xml" 2>/dev/null || true
                sudo chmod 644 "$gdm_dir/.config/monitors.xml"

                # If seat0 exists (GNOME 46+ dynamic seat sessions), also populate seat config dirs
                if [ -d "$gdm_dir/seat0" ]; then
                    sudo mkdir -p "$gdm_dir/seat0/config" "$gdm_dir/seat0/.config" 2>/dev/null || true
                    sudo cp -f "$user_monitors" "$gdm_dir/seat0/config/monitors.xml" 2>/dev/null || true
                    sudo cp -f "$user_monitors" "$gdm_dir/seat0/.config/monitors.xml" 2>/dev/null || true
                    sudo chown "$USER:" "$gdm_dir/seat0/config/monitors.xml" "$gdm_dir/seat0/.config/monitors.xml" 2>/dev/null || true
                    sudo chmod 644 "$gdm_dir/seat0/config/monitors.xml" "$gdm_dir/seat0/.config/monitors.xml" 2>/dev/null || true
                fi
                synced=1
            fi
        fi
    done

    if [ "$synced" = 1 ]; then
        if [ "${DRY_RUN:-0}" != 1 ]; then
            mkdir -p "$CONF_DIR"
            touch "$CONF_DIR/gdm-monitors-synced"
        fi
        ok "primary monitor synced to GDM login screen (good for multi-monitor setups)"
    fi
}

unsync_gdm_monitors() {
    step "Removing synced GDM monitor configuration (requires sudo)"

    local targets=(
        "/etc/xdg/monitors.xml"
        "/var/lib/gdm/.config/monitors.xml"
        "/var/lib/gdm3/.config/monitors.xml"
        "/var/lib/gdm/seat0/config/monitors.xml"
        "/var/lib/gdm/seat0/.config/monitors.xml"
        "/var/lib/gdm3/seat0/config/monitors.xml"
        "/var/lib/gdm3/seat0/.config/monitors.xml"
    )
    for target in "${targets[@]}"; do
        if [ -f "$target" ]; then
            if [ "${DRY_RUN:-0}" = 1 ]; then
                info "dry-run: sudo rm -f $target"
            else
                sudo rm -f "$target" 2>/dev/null || true
            fi
        fi
    done
    rm -f "$CONF_DIR/gdm-monitors-synced"
    ok "GDM monitor layout reverted to system default"
}

install_gdm_sync_unit() {
    if [ -f "$HOME/.config/systemd/user/tahoe-glass-gdm-sync.service" ]; then
        run systemctl --user disable --now tahoe-glass-gdm-sync.service >/dev/null 2>&1 || true
        run rm -f "$HOME/.config/systemd/user/tahoe-glass-gdm-sync.service"
    fi

    run install -Dm755 "$REPO_ROOT/bin/aura-glass-gdm-sync" \
        "$HOME/.local/bin/aura-glass-gdm-sync"
    ln -sf "$HOME/.local/bin/aura-glass-gdm-sync" "$HOME/.local/bin/tahoe-glass-gdm-sync" 2>/dev/null || true
    run install -Dm644 "$REPO_ROOT/systemd/aura-glass-gdm-sync.service" \
        "$HOME/.config/systemd/user/aura-glass-gdm-sync.service"
    run systemctl --user daemon-reload
    run systemctl --user enable aura-glass-gdm-sync.service >/dev/null 2>&1 || true

    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        run systemctl --user restart aura-glass-gdm-sync.service 2>/dev/null || true
    fi
    ok "GDM dynamic wallpaper sync daemon enabled"
}

uninstall_gdm_sync_unit() {
    for u in aura-glass-gdm-sync.service tahoe-glass-gdm-sync.service; do
        if [ -f "$HOME/.config/systemd/user/$u" ]; then
            run systemctl --user disable --now "$u" >/dev/null 2>&1 || true
            run rm -f "$HOME/.config/systemd/user/$u"
        fi
    done
    run systemctl --user daemon-reload
    run rm -f "$HOME/.local/bin/aura-glass-gdm-sync" "$HOME/.local/bin/tahoe-glass-gdm-sync"
}

have_image_processor() {
    python3 -c 'import PIL' >/dev/null 2>&1 || have magick
}

detect_gdm_theme_files() {
    local candidates=(
        "/usr/share/gnome-shell/gdm-theme.gresource"
        "/etc/alternatives/gdm-theme.gresource"
        "/usr/share/gnome-shell/theme/Yaru/gnome-shell-theme.gresource"
        "/usr/share/gnome-shell/theme/Yaru-dark/gnome-shell-theme.gresource"
        "/usr/share/gnome-shell/gnome-shell-theme.gresource"
    )

    for c in "${candidates[@]}"; do
        if [ -L "$c" ]; then
            local resolved
            resolved="$(readlink -f "$c" 2>/dev/null || true)"
            if [ -n "$resolved" ] && [ -f "$resolved" ]; then
                echo "$resolved"
                return 0
            fi
        elif [ -f "$c" ]; then
            echo "$c"
            return 0
        fi
    done

    echo "/usr/share/gnome-shell/gnome-shell-theme.gresource"
}

install_gdm() {
    local gdm_bg="${1:-${GDM_BG:-default}}"
    step "Installing the GDM Login Screen theme (requires sudo)"

    if ! have gdm && ! have gdm3 && [ ! -e /usr/sbin/gdm3 ]; then
        skip "GDM is not installed on this system"
        return 0
    fi

    if ! have glib-compile-resources; then
        local gcr_pkg
        case "$DISTRO_FAMILY" in
            arch)   gcr_pkg="glib2" ;;
            fedora) gcr_pkg="glib2-devel" ;;
            debian) gcr_pkg="libglib2.0-dev-bin" ;;
            *)      gcr_pkg="glib-compile-resources" ;;
        esac
        warn "glib-compile-resources missing (install $gcr_pkg for full shell theme rebuild)"
        info "Activating GDM fallback mode: syncing wallpaper and monitor layout..."

        # 1. Sync primary monitor layout to GDM if requested
        if [ "${WANT_GDM_MONITORS:-0}" = 1 ] && [ ! -f "$CONF_DIR/gdm-monitors-synced" ]; then
            sync_gdm_monitors
        fi

        # 2. Prepare initial blurred desktop wallpaper in /usr/share/backgrounds/aura-gdm.png
        local target_wall="/usr/share/backgrounds/aura-gdm.png"
        local wall_src; wall_src="$(resolve_gdm_wallpaper_source "$gdm_bg")"

        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: generate $target_wall from $wall_src"
        else
            sudo mkdir -p /usr/share/backgrounds
            local tmp_init
            tmp_init="$(mktemp /tmp/aura-gdm-init.XXXXXX.png)"
            if generate_gdm_wallpaper "$wall_src" "$tmp_init"; then
                sudo cp -f "$tmp_init" "$target_wall"
                rm -f "$tmp_init"
            else
                rm -f "$tmp_init"
                printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc`\x00\x00\x00\x02\x00\x01H\xaf\xa4q\x00\x00\x00\x00IEND\xaeB`\x82' | sudo tee "$target_wall" >/dev/null
            fi
            sudo chown "$USER:" "$target_wall"
            sudo chmod 644 "$target_wall"
        fi

        install_gdm_sync_unit
        if [ "${DRY_RUN:-0}" != 1 ]; then
            mkdir -p "$CONF_DIR"
            printf '%s\n' "fallback" > "$CONF_DIR/gdm-installed"
        fi
        ok "GDM configured in fallback mode (wallpaper & monitor sync active)"
        return 0
    fi

    if ! have_image_processor; then
        local pil_pkg
        case "$DISTRO_FAMILY" in
            arch)   pil_pkg="python-pillow" ;;
            fedora) pil_pkg="python3-pillow" ;;
            debian) pil_pkg="python3-pil" ;;
            *)      pil_pkg="python3-pil" ;;
        esac
        warn "Pillow or ImageMagick is required to blur the GDM wallpaper (install $pil_pkg)"
        return 1
    fi

    # 1. Sync primary monitor layout to GDM if requested
    if [ "${WANT_GDM_MONITORS:-0}" = 1 ] && [ ! -f "$CONF_DIR/gdm-monitors-synced" ]; then
        sync_gdm_monitors
    fi

    # 2. Prepare initial blurred desktop wallpaper in /usr/share/backgrounds/aura-gdm.png
    local target_wall="/usr/share/backgrounds/aura-gdm.png"
    local wall_src
    wall_src="$(resolve_gdm_wallpaper_source "$gdm_bg")"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: generate $target_wall from $wall_src and make writable for live wallpaper sync"
    else
        sudo mkdir -p /usr/share/backgrounds
        local tmp_init
        tmp_init="$(mktemp /tmp/aura-gdm-init.XXXXXX.png)"
        if generate_gdm_wallpaper "$wall_src" "$tmp_init"; then
            sudo cp -f "$tmp_init" "$target_wall"
            rm -f "$tmp_init"
        else
            rm -f "$tmp_init"
            # Fallback 1x1 valid PNG in the extreme case all generators fail
            printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc`\x00\x00\x00\x02\x00\x01H\xaf\xa4q\x00\x00\x00\x00IEND\xaeB`\x82' | sudo tee "$target_wall" >/dev/null
        fi
        sudo chown "$USER:" "$target_wall"
        sudo chmod 644 "$target_wall"
        ok "GDM background configured from $wall_src ($target_wall)"
    fi

    # 3. Compile and install GDM theme patched to link directly to file:///usr/share/backgrounds/aura-gdm.png
    info "Preparing WhiteSur GDM resources..."
    local src="$SRC_CACHE/WhiteSur-gtk-theme"
    clone_pinned "$WHITESUR_REPO" "$WHITESUR_REF" "$src"

    local gdm_res
    gdm_res="$(detect_gdm_theme_files)"
    local gdm_backup_record="$CONF_DIR/gdm-backup-path"
    local gdm_backup_file=""

    if [ -f "$gdm_res" ]; then
        gdm_backup_file="${gdm_res}.aura-backup"
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: sudo cp -f $gdm_res $gdm_backup_file"
        else
            sudo cp -f "$gdm_res" "$gdm_backup_file" 2>/dev/null || true
            mkdir -p "$CONF_DIR"
            echo "$gdm_backup_file" > "$gdm_backup_record"
        fi
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: compile GDM theme with background linking to $target_wall"
    else
        # Patch theme css so GDM directly loads file:///usr/share/backgrounds/aura-gdm.png
        sed -i 's|resource:///org/gnome/shell/theme/background.png|file:///usr/share/backgrounds/aura-gdm.png|g' \
            "$src"/other/gdm/theme/gnome-shell-*.css 2>/dev/null || true
        sed -i 's|assets/background.png|file:///usr/share/backgrounds/aura-gdm.png|g' \
            "$src"/src/main/gnome-shell/gnome-shell-*.css 2>/dev/null || true

        # Neutralize WhiteSur internal network & system package checks that can freeze/hang
        sed -i 's/prepare_deps/true/g' "$src"/libs/*.sh 2>/dev/null || true
        sed -i 's/get_utc_epoch_time/true/g' "$src"/libs/*.sh 2>/dev/null || true

        info "Compiling and applying GDM theme..."
        sudo -v || { warn "sudo authentication required for GDM installation"; return 1; }

        local gdm_log
        gdm_log="$(mktemp /tmp/aura-gdm-install.XXXXXX.log)"
        # shellcheck disable=SC2024
        if sudo bash "$src/tweaks.sh" -g -b "$target_wall" -nb --silent-mode >"$gdm_log" 2>&1; then
            mkdir -p "$CONF_DIR"
            printf '%s\n' "dynamic" > "$CONF_DIR/gdm-installed"
            ok "GDM login screen theme installed (dynamic wallpaper sync)"
            rm -f "$gdm_log"
        else
            warn "GDM theme installation failed (log: $gdm_log)"
            if [ -f "$gdm_log" ]; then
                grep -E "ERROR|error|failed|fatal" "$gdm_log" | head -n 5 | while read -r err_line; do
                    warn "  $err_line"
                done
            fi
            # Automatic rollback fallback: restore original gresource if modified or corrupted
            if [ -n "$gdm_backup_file" ] && [ -f "$gdm_backup_file" ]; then
                warn "Triggering automatic GDM rollback fallback..."
                sudo cp -f "$gdm_backup_file" "$gdm_res" 2>/dev/null || true
                rm -f "$gdm_backup_record"
                ok "GDM stock theme safely restored after failed build"
            fi
            rm -f "$gdm_log"

            # Fall back cleanly to background & monitor sync
            mkdir -p "$CONF_DIR"
            printf '%s\n' "fallback" > "$CONF_DIR/gdm-installed"
            install_gdm_sync_unit
            ok "GDM configured in fallback mode (wallpaper & monitor sync active)"
            return 0
        fi
    fi

    # 4. Install and start user daemon for live wallpaper updates
    install_gdm_sync_unit
}

uninstall_gdm() {
    step "Restoring default GDM login screen"

    local src="$SRC_CACHE/WhiteSur-gtk-theme"
    local restored=0

    if [ -f "$src/tweaks.sh" ]; then
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: sudo bash $src/tweaks.sh -r -g --silent-mode"
            restored=1
        else
            sudo -v 2>/dev/null || true
            sed -i 's/prepare_deps/true/g' "$src"/libs/*.sh 2>/dev/null || true
            sed -i 's/get_utc_epoch_time/true/g' "$src"/libs/*.sh 2>/dev/null || true
            if sudo bash "$src/tweaks.sh" -r -g --silent-mode >/dev/null 2>&1; then
                restored=1
            fi
        fi
    fi

    # Fallback to direct backup file restoration if tweaks.sh didn't run or failed
    if [ "$restored" = 0 ]; then
        local gdm_res
        gdm_res="$(detect_gdm_theme_files)"
        local recorded_bak=""
        [ -f "$CONF_DIR/gdm-backup-path" ] && recorded_bak="$(cat "$CONF_DIR/gdm-backup-path" 2>/dev/null || true)"

        local backup_candidates=(
            "$recorded_bak"
            "${gdm_res}.aura-backup"
            "${gdm_res}.bak"
            "/usr/share/gnome-shell/gnome-shell-theme.gresource.bak"
            "/usr/share/gnome-shell/gdm-theme.gresource.bak"
            "/usr/share/gnome-shell/theme/Yaru/gnome-shell-theme.gresource.bak"
        )

        for bak in "${backup_candidates[@]}"; do
            if [ -n "$bak" ] && [ -f "$bak" ]; then
                if [ "${DRY_RUN:-0}" = 1 ]; then
                    info "dry-run: sudo cp -f $bak $gdm_res"
                else
                    sudo cp -f "$bak" "$gdm_res" 2>/dev/null || true
                fi
                restored=1
                break
            fi
        done

        if [ "$restored" = 1 ] && [ -e /etc/alternatives/gdm-theme.gresource ] && command -v update-alternatives >/dev/null 2>&1; then
            if [ "${DRY_RUN:-0}" != 1 ]; then
                sudo update-alternatives --auto gdm-theme.gresource 2>/dev/null || true
            fi
        fi
    fi

    # Clean up recorded backup path
    rm -f "$CONF_DIR/gdm-backup-path"

    # Remove dynamic background file
    for bg_file in "/usr/share/backgrounds/aura-gdm.png" "/usr/share/backgrounds/tahoe-gdm.png"; do
        if [ -f "$bg_file" ]; then
            if [ "${DRY_RUN:-0}" = 1 ]; then
                info "dry-run: sudo rm -f $bg_file"
            else
                sudo rm -f "$bg_file" 2>/dev/null || true
            fi
        fi
    done

    # Disable sync unit
    uninstall_gdm_sync_unit

    rm -f "$CONF_DIR/gdm-installed"
    if [ "$restored" = 1 ]; then
        ok "GDM login screen restored to stock theme"
    else
        skip "GDM theme was not installed or backup not found"
    fi
}
