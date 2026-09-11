#!/usr/bin/env bash
# Assert aura-glass-daemon lifecycle, service file generation, and CLI delegation.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
DAEMON_BIN="$REPO_ROOT/bin/aura-glass-daemon"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help
[ -x "$DAEMON_BIN" ] || note "bin/aura-glass-daemon is not executable"
out_help="$("$DAEMON_BIN" --help)" || note "aura-glass-daemon --help failed"
[[ "$out_help" =~ "aura-glass-daemon" ]] || note "--help output missing command name"

# 2. Test in isolated environment
TEST_CONF="$(mktemp -d)"
export AURA_GLASS_CONF="$TEST_CONF"
export XDG_CONFIG_HOME="$TEST_CONF/config"
mkdir -p "$XDG_CONFIG_HOME"
trap 'rm -rf "$TEST_CONF"' EXIT

# 3. Check status when stopped
out_status="$("$DAEMON_BIN" status)" || note "daemon status failed"
[[ "$out_status" =~ "Inactive" ]] || note "daemon status not showing inactive"
[[ "$out_status" =~ "Active Capabilities" ]] || note "daemon status missing capabilities section"

# 4. Check systemd service installation
"$DAEMON_BIN" install-service >/dev/null 2>&1 || note "install-service failed"
service_file="$XDG_CONFIG_HOME/systemd/user/aura-glass.service"
[ -f "$service_file" ] || note "service file not generated at $service_file"

# Check unit file contents
grep -q "Description=Aura Glass" "$service_file" || note "missing Description in service file"
grep -q "ExecStart=" "$service_file" || note "missing ExecStart in service file"
grep -q "WantedBy=graphical-session.target" "$service_file" || note "missing WantedBy in service file"

# 5. Check uninstall service
"$DAEMON_BIN" uninstall-service >/dev/null 2>&1 || note "uninstall-service failed"
[ ! -f "$service_file" ] || note "service file still exists after uninstall-service"

# 6. Check logs command
out_logs="$("$DAEMON_BIN" logs)" || note "daemon logs failed"
[[ "$out_logs" =~ "No log entries found" ]] || note "daemon logs unexpected output on empty log"

echo "dummy log entry" > "$TEST_CONF/daemon.log"
out_logs2="$("$DAEMON_BIN" logs)" || note "daemon logs with file failed"
[[ "$out_logs2" =~ "dummy log entry" ]] || note "daemon logs did not return log content"

# 7. Check CLI delegation via aura-glass
out_cli_daemon="$("$CLI" daemon status)" || note "aura-glass daemon status delegation failed"
[[ "$out_cli_daemon" =~ "Aura Glass Background Daemon" ]] || note "CLI daemon status missing output"

if [ "$fail" -eq 1 ]; then
    printf 'check-daemon.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-daemon.sh: passed (daemon lifecycle, systemd unit, & CLI delegation verified)\n'
