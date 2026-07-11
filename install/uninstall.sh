#!/bin/bash
#
# Uninstaller for the One Fellowship Kids Notification Service (of-notifier).
#
# What this does:
#   1. Stops and removes the LaunchAgent so the service no longer runs at
#      login or restarts on crash.
#   2. Removes the global wrapper command (/usr/local/bin/of-notifier).
#   3. Removes the app directory (/usr/local/opt/of-notifier), including the
#      .env secrets file — after confirmation, since this step is
#      irreversible.
#
# Shared system dependencies (Homebrew, uv, Node, Xcode Command Line Tools)
# are left untouched, since they aren't exclusive to this app.
#
# Run as your normal user (not with sudo) — the script escalates via `sudo`
# only for the specific steps that need it.

set -euo pipefail

INSTALL_DIR="/usr/local/opt/of-notifier"
BIN_LINK="/usr/local/bin/of-notifier"
LAUNCH_AGENT_LABEL="local.of-notifier"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m==> warning:\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31m==> error:\033[0m %s\n' "$1" >&2; exit 1; }

require_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        die "Run this script as your normal user, not with sudo. It will ask for your password via sudo when it needs to."
    fi
}

confirm() {
    local prompt="$1" reply
    read -rp "$prompt [y/N]: " reply
    [[ "$reply" =~ ^[Yy] ]]
}

remove_launch_agent() {
    if [[ ! -f "$LAUNCH_AGENT_PLIST" ]]; then
        log "LaunchAgent not installed — skipping."
        return
    fi
    log "Stopping and removing LaunchAgent ($LAUNCH_AGENT_LABEL)..."
    local uid
    uid="$(id -u)"
    launchctl bootout "gui/$uid" "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT_PLIST"
    log "LaunchAgent removed."
}

remove_wrapper() {
    if [[ ! -e "$BIN_LINK" ]]; then
        log "Global command not installed — skipping."
        return
    fi
    log "Removing global command: $BIN_LINK"
    sudo rm -f "$BIN_LINK"
}

remove_app_dir() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log "App directory not installed — skipping."
        return
    fi
    warn "This will permanently delete $INSTALL_DIR, including its .env secrets file."
    if ! confirm "Remove $INSTALL_DIR?"; then
        log "Skipping app directory removal."
        return
    fi
    log "Removing app directory: $INSTALL_DIR"
    sudo rm -rf "$INSTALL_DIR"
}

main() {
    require_not_root

    remove_launch_agent
    remove_wrapper
    remove_app_dir

    cat <<EOF

==> of-notifier uninstalled.

Homebrew and any dependencies it installed (uv, node, etc.) were left in
place, since they aren't exclusive to this app.
EOF
}

main "$@"
