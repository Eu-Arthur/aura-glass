# shellcheck shell=bash
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
        COMPREPLY=( $(compgen -W "--json --quiet -q --help -h" -- "$cur") )
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

_aura_glass_main() {
    local cur prev subcmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    subcmds="status mode doctor settings backup apply gdm update ext preview version help"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$subcmds -h --help -v --version" -- "$cur") )
        return 0
    fi

    local cmd="${COMP_WORDS[1]}"
    case "$cmd" in
        mode)
            _aura_glass_mode
            ;;
        doctor)
            _aura_glass_doctor
            ;;
        backup)
            _aura_glass_backup
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
complete -F _aura_glass_main aura-glass ./bin/aura-glass bin/aura-glass

