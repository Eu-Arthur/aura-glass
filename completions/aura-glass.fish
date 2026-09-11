# Fish completion for Aura Glass suite

# Shared options for installer and apply tool
for cmd in install.sh aura-glass-apply
    complete -c $cmd -f
    complete -c $cmd -l full -d "Install full suite with all extensions and extras"
    complete -c $cmd -l extras -d "Install extra extensions"
    complete -c $cmd -l no-extras -d "Skip extra extensions"
    complete -c $cmd -l accent -r -f -a "blue teal green yellow orange red pink purple slate" -d "Theme accent color"
    complete -c $cmd -l glass-mode -r -f -a "frosted transparent solid" -d "Glass transparency mode"
    complete -c $cmd -l blur-mode -r -f -a "frosted transparent solid" -d "Glass transparency mode"
    complete -c $cmd -l radius-preset -r -f -a "flat sharp adwaita soft medium default rounded custom" -d "Corner radius preset"
    complete -c $cmd -l font -r -f -a "system inter misans sf-pro" -d "Interface font"
    complete -c $cmd -l icons -r -f -a "colloid reversal mactahoe hatter keep original" -d "Icon pack"
    complete -c $cmd -l cursors -r -f -a "aosp mactahoe keep original" -d "Cursor theme"
    complete -c $cmd -l blur -d "Enable blur effects"
    complete -c $cmd -l no-blur -d "Disable blur effects"
    complete -c $cmd -l popup-blur -d "Enable popup blur"
    complete -c $cmd -l no-popup-blur -d "Disable popup blur"
    complete -c $cmd -l static-popup-blur -d "Static popup blur"
    complete -c $cmd -l notification-blur -d "Enable notification blur"
    complete -c $cmd -l no-notification-blur -d "Disable notification blur"
    complete -c $cmd -l app-transparency -r -f -a "0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0" -d "Window transparency"
    complete -c $cmd -l panel-transparency -r -f -a "0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0" -d "Top panel transparency"
    complete -c $cmd -l gdm -d "Configure GDM login screen blur and styling"
    complete -c $cmd -l no-gdm -d "Skip GDM configuration"
    complete -c $cmd -l gdm-monitors -d "Sync monitors.xml to GDM"
    complete -c $cmd -l reinstall -d "Force reinstallation"
    complete -c $cmd -l update -d "Update Aura Glass installation"
    complete -c $cmd -s n -l dry-run -d "Simulate execution"
    complete -c $cmd -l interactive -d "Interactive prompts"
    complete -c $cmd -s y -l yes -d "Assume yes to all prompts"
    complete -c $cmd -l settings-only -d "Apply settings without reinstalling dependencies"
    complete -c $cmd -l styling-off -d "Disable styling (solid mode)"
    complete -c $cmd -l styling-on -d "Restore styling"
    complete -c $cmd -l doctor -d "Run diagnostic checks"
    complete -c $cmd -s h -l help -d "Show usage help"
end

# Main unified CLI
complete -c aura-glass -f
complete -c aura-glass -n "__fish_use_subcommand" -a "status mode accent shortcut doctor settings backup apply gdm update ext preview version help"
complete -c aura-glass -s h -l help -d "Show usage help"
complete -c aura-glass -s v -l version -d "Print version"
complete -c aura-glass -n "__fish_seen_subcommand_from mode" -a "get set toggle eco auto frosted transparent solid"
complete -c aura-glass -n "__fish_seen_subcommand_from accent" -a "get auto set list blue teal green yellow orange red pink purple slate"
complete -c aura-glass -n "__fish_seen_subcommand_from shortcut" -a "status enable disable"
complete -c aura-glass -n "__fish_seen_subcommand_from gdm" -a "sync"
complete -c aura-glass -n "__fish_seen_subcommand_from ext" -a "list install remove enable disable recommended full"
complete -c aura-glass -n "__fish_seen_subcommand_from backup" -a "create export import restore list verify"

# Uninstall tool
complete -c uninstall.sh -f
complete -c uninstall.sh -l all -d "Remove all components and configurations"
complete -c uninstall.sh -l full -d "Alias for --all"
complete -c uninstall.sh -l extensions -d "Remove extensions"
complete -c uninstall.sh -l assets -d "Remove themes, icons, and fonts"
complete -c uninstall.sh -l gdm -d "Revert GDM configuration"
complete -c uninstall.sh -l gdm-monitors -d "Remove GDM monitors sync"
complete -c uninstall.sh -l interactive -d "Interactive confirmation"
complete -c uninstall.sh -s y -l yes -d "Assume yes to uninstall prompts"
complete -c uninstall.sh -s n -l dry-run -d "Simulate uninstallation"
complete -c uninstall.sh -s h -l help -d "Show uninstall help"

# Extension manager
complete -c aura-glass-ext -f
complete -c aura-glass-ext -n "__fish_use_subcommand" -a "list install remove enable disable recommended full"
complete -c aura-glass-ext -s h -l help -d "Show help"

set -l _ext_uuids user-theme@gnome-shell-extensions.gcampax.github.com \
    openbar@neuromorph blur-my-shell@aunetx custom-osd@neuromorph \
    just-perfection-desktop@just-perfection gnome-ui-tune@itstime.tech \
    space-bar@luchrioh appindicatorsupport@rgcjonas.gmail.com \
    clipboard-indicator@tudmotu.com compiz-alike-magic-lamp-effect@hermes83.github.com \
    Vitals@CoreCoding.com auto-accent-colour@Wartybix ddterm@amezin.github.com \
    kiwimenu@kemma hotedge@jonathan.jdoda.ca restartto@tiagoporsch.github.io \
    xwayland-indicator@swsnr.de add-to-steam@pupper.space

for sub in install remove enable disable
    complete -c aura-glass-ext -n "__fish_seen_subcommand_from $sub" -a "$_ext_uuids"
end

# Diagnostic doctor
complete -c aura-glass-doctor -f
complete -c aura-glass-doctor -l fix -d "Automatically remediate safe configuration issues"
complete -c aura-glass-doctor -l json -d "JSON output"
complete -c aura-glass-doctor -s q -l quiet -d "Quiet output"
complete -c aura-glass-doctor -s h -l help -d "Show help"

# Backup tool
complete -c aura-glass-backup -f
complete -c aura-glass-backup -n "__fish_use_subcommand" -a "create export import restore list verify"
complete -c aura-glass-backup -n "__fish_seen_subcommand_from export import restore verify" -F
complete -c aura-glass-backup -s h -l help -d "Show backup help"

# Mode switcher
complete -c aura-glass-mode -f
complete -c aura-glass-mode -n "__fish_use_subcommand" -a "get set toggle eco auto frosted transparent solid"
complete -c aura-glass-mode -n "__fish_seen_subcommand_from set" -a "frosted transparent solid"
complete -c aura-glass-mode -n "__fish_seen_subcommand_from eco" -a "on off"
complete -c aura-glass-mode -n "__fish_seen_subcommand_from auto" -a "on off status"
complete -c aura-glass-mode -l notify -d "Show desktop notification"
complete -c aura-glass-mode -s h -l help -d "Show mode help"

# Update check tool
complete -c aura-glass-update-check -f
complete -c aura-glass-update-check -l notify -d "Notify desktop if update available"
complete -c aura-glass-update-check -s h -l help -d "Show help"
