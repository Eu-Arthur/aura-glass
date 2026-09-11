# shellcheck shell=bash
# shellcheck disable=SC2207
# bash/zsh completion for aura-glass scripts and commands

if [ -n "${ZSH_VERSION:-}" ]; then
    autoload -U +X bashcompinit 2>/dev/null && bashcompinit
fi

_aura_glass_install() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
        --accent)
            COMPREPLY=( $(compgen -W "blue teal green yellow orange red pink purple slate" -- "$cur") )
            return 0
            ;;
        --glass-mode|--blur-mode)
            COMPREPLY=( $(compgen -W "frosted transparent solid" -- "$cur") )
            return 0
            ;;
        --radius-preset)
            COMPREPLY=( $(compgen -W "flat sharp adwaita soft medium default rounded custom" -- "$cur") )
            return 0
            ;;
        --font)
            COMPREPLY=( $(compgen -W "system inter misans sf-pro" -- "$cur") )
            return 0
            ;;
        --icons)
            COMPREPLY=( $(compgen -W "colloid reversal mactahoe hatter keep original" -- "$cur") )
            return 0
            ;;
        --cursors)
            COMPREPLY=( $(compgen -W "aosp mactahoe keep original" -- "$cur") )
            return 0
            ;;
        --app-transparency|--panel-transparency)
            COMPREPLY=( $(compgen -W "0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0" -- "$cur") )
            return 0
            ;;
    esac

    opts="--full --extras --no-extras --accent --glass-mode --blur-mode --radius-preset \
          --font --icons --cursors --blur --no-blur --popup-blur --no-popup-blur \
          --static-popup-blur --notification-blur --no-notification-blur \
          --app-transparency --panel-transparency --gdm --no-gdm --gdm-monitors \
          --reinstall --update --dry-run -n --interactive -y --yes --help -h \
          --settings-only --styling-off --styling-on --doctor"

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi
}

_aura_glass_uninstall() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    opts="--all --full --extensions --assets --gdm --gdm-monitors \
          --interactive -y --yes -n --dry-run -h --help"

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi
}

_aura_glass_update_check() {
    local cur opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    opts="--notify -h --help"
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi
}

_aura_glass_ext() {
    local cur prev subcmds uuids
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    subcmds="list install remove enable disable recommended full -h --help"
    uuids="user-theme@gnome-shell-extensions.gcampax.github.com \
           openbar@neuromorph blur-my-shell@aunetx custom-osd@neuromorph \
           just-perfection-desktop@just-perfection gnome-ui-tune@itstime.tech \
           space-bar@luchrioh appindicatorsupport@rgcjonas.gmail.com \
           clipboard-indicator@tudmotu.com compiz-alike-magic-lamp-effect@hermes83.github.com \
           Vitals@CoreCoding.com auto-accent-colour@Wartybix ddterm@amezin.github.com \
           kiwimenu@kemma hotedge@jonathan.jdoda.ca restartto@tiagoporsch.github.io \
           xwayland-indicator@swsnr.de add-to-steam@pupper.space"

    case "$prev" in
        install|remove|enable|disable)
            COMPREPLY=( $(compgen -W "$uuids" -- "$cur") )
            return 0
            ;;
    esac

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
        return 0
    fi
}

_aura_glass_doctor() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "--json --quiet -q --fix --help -h" -- "$cur") )
        return 0
    fi
}

_aura_glass_backup() {
    local cur prev subcmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    subcmds="create export import restore list verify -h --help"

    case "$prev" in
        export|import|restore|verify)
            COMPREPLY=( $(compgen -f -X '!*.tar.gz' -- "$cur") $(compgen -f -X '!*.tgz' -- "$cur") )
            return 0
            ;;
    esac

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
        return 0
    fi
}

_aura_glass_mode() {
    local cur prev subcmds modes
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    modes="frosted transparent solid"
    subcmds="get set toggle eco auto frosted transparent solid --notify -h --help"

    case "$prev" in
        set)
            COMPREPLY=( $(compgen -W "$modes" -- "$cur") )
            return 0
            ;;
        eco)
            COMPREPLY=( $(compgen -W "on off" -- "$cur") )
            return 0
            ;;
        auto|auto-eco|auto-power)
            COMPREPLY=( $(compgen -W "on off status" -- "$cur") )
            return 0
            ;;
    esac

    COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
}

_aura_glass_profile() {
    local cur prev subcmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    subcmds="list apply save current export import remove -h --help"

    case "$prev" in
        apply|export|remove)
            COMPREPLY=( $(compgen -W "sonoma visionos nordic minimal cyberpunk eco" -- "$cur") )
            return 0
            ;;
        import)
            COMPREPLY=( $(compgen -f -X '!*.json' -- "$cur") )
            return 0
            ;;
    esac

    COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
}

_aura_glass_daemon() {
    local cur prev subcmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    subcmds="status start stop restart run logs install-service uninstall-service -h --help"
    COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
}

_aura_glass_terminal() {
    local cur prev subcmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    subcmds="status sync apply snippet -h --help"

    case "$prev" in
        apply|snippet)
            COMPREPLY=( $(compgen -W "ghostty kitty alacritty wezterm foot ptyxis" -- "$cur") )
            return 0
            ;;
    esac

    COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
}

_aura_glass_adaptive() {
    local cur prev subcmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    subcmds="status enable disable sync trigger -h --help"

    case "$prev" in
        trigger)
            COMPREPLY=( $(compgen -W "day night" -- "$cur") )
            return 0
            ;;
        --day|--night)
            COMPREPLY=( $(compgen -W "sonoma visionos nordic minimal cyberpunk eco" -- "$cur") )
            return 0
            ;;
    esac

    COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
}

_aura_glass_bench() {
    local cur opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    opts="--json --quick --tune --apply -h --help"
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
}

_aura_glass_browser() {
    local cur prev subcmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    subcmds="status firefox snippet -h --help"

    case "$prev" in
        firefox)
            COMPREPLY=( $(compgen -W "enable disable sync status snippet -h --help" -- "$cur") )
            return 0
            ;;
    esac

    COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
}

_aura_glass_wallpaper() {
    local cur prev subcmds opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    subcmds="generate apply current -h --help"

    case "$prev" in
        --accent)
            COMPREPLY=( $(compgen -W "blue teal green yellow orange red pink purple slate" -- "$cur") )
            return 0
            ;;
        apply)
            compopt -o default 2>/dev/null || true
            return 0
            ;;
    esac

    if [ "$COMP_CWORD" -eq 1 ] || { [ "${COMP_WORDS[1]}" = "wallpaper" ] && [ "$COMP_CWORD" -eq 2 ]; }; then
        COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
        return 0
    fi

    opts="--mesh --aurora --obsidian --accent --width --height --output --apply -h --help"
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi
}

_aura_glass_glow() {
    local cur prev subcmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    subcmds="status on off toggle -h --help"

    case "$prev" in
        --style)
            COMPREPLY=( $(compgen -W "subtle accent neon" -- "$cur") )
            return 0
            ;;
    esac

    if [ "$COMP_CWORD" -eq 1 ] || { [ "${COMP_WORDS[1]}" = "glow" ] && [ "$COMP_CWORD" -eq 2 ]; }; then
        COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
        return 0
    fi

    if [ "$prev" = "on" ]; then
        COMPREPLY=( $(compgen -W "--style -h --help" -- "$cur") )
        return 0
    fi
}

_aura_glass_sound() {
    local cur prev subcmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    subcmds="status enable disable preview -h --help"

    case "$prev" in
        preview)
            COMPREPLY=( $(compgen -W "bell screen-capture window-tile volume" -- "$cur") )
            return 0
            ;;
    esac

    if [ "$COMP_CWORD" -eq 1 ] || { [ "${COMP_WORDS[1]}" = "sound" ] && [ "$COMP_CWORD" -eq 2 ]; }; then
        COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
        return 0
    fi
}

_aura_glass_apps() {
    local cur prev subcmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    subcmds="status apply revert snippet -h --help"

    case "$prev" in
        apply|revert)
            COMPREPLY=( $(compgen -W "vscode obsidian all" -- "$cur") )
            return 0
            ;;
        snippet)
            COMPREPLY=( $(compgen -W "vscode obsidian" -- "$cur") )
            return 0
            ;;
    esac

    if [ "$COMP_CWORD" -eq 1 ] || { [ "${COMP_WORDS[1]}" = "apps" ] && [ "$COMP_CWORD" -eq 2 ]; }; then
        COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
        return 0
    fi
}

_aura_glass_main() {
    local cur prev subcmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    subcmds="status profile mode accent adaptive shortcut bench browser terminal daemon doctor settings backup apply gdm update wallpaper glow sound apps ext preview version help"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$subcmds -h --help -v --version" -- "$cur") )
        return 0
    fi

    local cmd="${COMP_WORDS[1]}"
    case "$cmd" in
        profile|profiles)
            _aura_glass_profile
            ;;
        mode)
            _aura_glass_mode
            ;;
        accent)
            if [ "$COMP_CWORD" -eq 2 ]; then
                COMPREPLY=( $(compgen -W "auto get set list blue teal green yellow orange red pink purple slate -h --help" -- "$cur") )
            elif [ "$COMP_CWORD" -eq 3 ] && [ "$prev" = "set" ]; then
                COMPREPLY=( $(compgen -W "blue teal green yellow orange red pink purple slate" -- "$cur") )
            fi
            ;;
        adaptive)
            _aura_glass_adaptive
            ;;
        bench|benchmark)
            _aura_glass_bench
            ;;
        browser|browsers)
            _aura_glass_browser
            ;;
        shortcut|shortcuts)
            if [ "$COMP_CWORD" -eq 2 ]; then
                COMPREPLY=( $(compgen -W "status enable disable -h --help" -- "$cur") )
            fi
            ;;
        terminal|terminals)
            _aura_glass_terminal
            ;;
        daemon)
            _aura_glass_daemon
            ;;
        doctor)
            _aura_glass_doctor
            ;;
        backup)
            _aura_glass_backup
            ;;
        wallpaper|wallpapers)
            _aura_glass_wallpaper
            ;;
        glow)
            _aura_glass_glow
            ;;
        sound|sounds)
            _aura_glass_sound
            ;;
        apps|app)
            _aura_glass_apps
            ;;
        ext)
            _aura_glass_ext
            ;;
        gdm)
            COMPREPLY=( $(compgen -W "sync" -- "$cur") )
            ;;
    esac
}

complete -F _aura_glass_install install.sh ./install.sh aura-glass-apply ./bin/aura-glass-apply bin/aura-glass-apply
complete -F _aura_glass_uninstall uninstall.sh ./uninstall.sh
complete -F _aura_glass_update_check aura-glass-update-check ./bin/aura-glass-update-check bin/aura-glass-update-check
complete -F _aura_glass_ext aura-glass-ext ./bin/aura-glass-ext bin/aura-glass-ext
complete -F _aura_glass_doctor aura-glass-doctor ./bin/aura-glass-doctor bin/aura-glass-doctor
complete -F _aura_glass_backup aura-glass-backup ./bin/aura-glass-backup bin/aura-glass-backup
complete -F _aura_glass_mode aura-glass-mode ./bin/aura-glass-mode bin/aura-glass-mode
complete -F _aura_glass_profile aura-glass-profile ./bin/aura-glass-profile bin/aura-glass-profile
complete -F _aura_glass_daemon aura-glass-daemon ./bin/aura-glass-daemon bin/aura-glass-daemon
complete -F _aura_glass_terminal aura-glass-terminal ./bin/aura-glass-terminal bin/aura-glass-terminal
complete -F _aura_glass_adaptive aura-glass-adaptive ./bin/aura-glass-adaptive bin/aura-glass-adaptive
complete -F _aura_glass_bench aura-glass-bench ./bin/aura-glass-bench bin/aura-glass-bench
complete -F _aura_glass_browser aura-glass-browser ./bin/aura-glass-browser bin/aura-glass-browser
complete -F _aura_glass_wallpaper aura-glass-wallpaper ./bin/aura-glass-wallpaper bin/aura-glass-wallpaper
complete -F _aura_glass_glow aura-glass-glow ./bin/aura-glass-glow bin/aura-glass-glow
complete -F _aura_glass_sound aura-glass-sound ./bin/aura-glass-sound bin/aura-glass-sound
complete -F _aura_glass_apps aura-glass-apps ./bin/aura-glass-apps bin/aura-glass-apps
complete -F _aura_glass_main aura-glass ./bin/aura-glass bin/aura-glass



