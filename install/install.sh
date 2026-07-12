#!/bin/bash
#
# Installer for the One Fellowship Kids Notification Service (of-notifier).
#
# What this does:
#   1. Verifies/installs Xcode Command Line Tools, Homebrew, uv, and Node/npm.
#   2. Copies the app into /usr/local/opt/of-notifier and exposes it globally
#      as `of-notifier` via a wrapper in /usr/local/bin.
#   3. Runs `uv sync` then `uv run build` in the install directory.
#   4. Prompts for the required environment variables and writes a
#      owner-only-readable .env file.
#   5. Installs a per-user LaunchAgent so the service starts at login and
#      restarts if it crashes.
#
# Run as your normal user (not with sudo) — the script escalates via `sudo`
# only for the specific steps that need it.

set -euo pipefail

INSTALL_DIR="/usr/local/opt/of-notifier"
BIN_LINK="/usr/local/bin/of-notifier"
LAUNCH_AGENT_LABEL="local.of-notifier"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m==> warning:\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31m==> error:\033[0m %s\n' "$1" >&2; exit 1; }

require_macos() {
    [[ "$(uname -s)" == "Darwin" ]] || die "This installer only supports macOS."
}

require_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        die "Run this script as your normal user, not with sudo. It will ask for your password via sudo when it needs to."
    fi
}

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

install_xcode_clt() {
    if xcode-select -p &>/dev/null; then
        log "Xcode Command Line Tools already installed."
        return
    fi
    log "Installing Xcode Command Line Tools (Apple-signed installer)..."
    xcode-select --install
    log "Waiting for the Xcode Command Line Tools installer to finish — complete the GUI prompt that just opened."
    until xcode-select -p &>/dev/null; do
        sleep 5
    done
    log "Xcode Command Line Tools installed."
}

brew_bin() {
    if command -v brew &>/dev/null; then
        command -v brew
    elif [[ -x /opt/homebrew/bin/brew ]]; then
        echo /opt/homebrew/bin/brew
    elif [[ -x /usr/local/bin/brew ]]; then
        echo /usr/local/bin/brew
    fi
}

install_homebrew() {
    if [[ -n "$(brew_bin)" ]]; then
        log "Homebrew already installed."
        return
    fi
    log "Installing Homebrew (official installer, verified over HTTPS)..."
    local installer
    installer="$(mktemp)"
    curl --proto '=https' --tlsv1.2 -fsSL \
        -o "$installer" \
        https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
    /bin/bash "$installer"
    rm -f "$installer"
}

ensure_brew_shellenv() {
    local brew
    brew="$(brew_bin)"
    [[ -n "$brew" ]] || die "Homebrew installation failed — brew not found."
    eval "$("$brew" shellenv)"
}

# Homebrew verifies SHA-256 checksums and bottle signatures for everything it
# installs, so formulae installed this way satisfy the integrity requirement
# without extra pinned hashes here.
brew_install_if_missing() {
    local formula="$1"
    if brew list --formula --versions "$formula" &>/dev/null; then
        log "$formula already installed via Homebrew."
    else
        log "Installing $formula via Homebrew..."
        brew install "$formula"
    fi
}

install_node() {
    brew_install_if_missing node
}

install_uv() {
    brew_install_if_missing uv
}

# uv manages its own Python builds (python-build-standalone), downloaded and
# hash-verified by uv itself — more correct for a uv-based project than
# installing a system Python via Homebrew.
install_python() {
    log "Ensuring Python 3.14 is available via uv..."
    uv python install 3.14
}

# ---------------------------------------------------------------------------
# App install
# ---------------------------------------------------------------------------

install_app_files() {
    log "Installing app files to $INSTALL_DIR..."
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown "$(id -un)":"$(id -gn)" "$INSTALL_DIR"

    rsync -a --delete \
        --exclude='.git' \
        --exclude='.venv' \
        --exclude='node_modules' \
        --exclude='__pycache__' \
        --exclude='.env' \
        --exclude='install' \
        "$REPO_ROOT"/ "$INSTALL_DIR"/

    mkdir -p "$INSTALL_DIR/logs"
}

install_wrapper() {
    log "Installing global command: $BIN_LINK"
    local uv_bin
    uv_bin="$(command -v uv)"
    sudo tee "$BIN_LINK" >/dev/null <<EOF
#!/bin/bash
export PATH=$PATH:/opt/homebrew/bin/
exec "$uv_bin" run --project "$INSTALL_DIR" start "\$@"
EOF
    sudo chmod 755 "$BIN_LINK"
}

sync_and_build() {
    log "Running uv sync..."
    (cd "$INSTALL_DIR" && uv sync)
    log "Running uv run build..."
    (cd "$INSTALL_DIR" && uv run build)
}

# ---------------------------------------------------------------------------
# .env
# ---------------------------------------------------------------------------

prompt_var() {
    local prompt="$1" default="${2:-}" value
    if [[ -n "$default" ]]; then
        read -rp "$prompt [$default]: " value
        echo "${value:-$default}"
    else
        read -rp "$prompt: " value
        echo "$value"
    fi
}

prompt_secret() {
    local prompt="$1" value
    read -rsp "$prompt: " value
    echo >&2
    echo "$value"
}

# Repeatedly asks for a phone number to add to the allow list, then asks
# whether to add another or move on. Leaving the first entry blank skips
# the allow list entirely (all senders will be allowed).
prompt_allowed_numbers() {
    local numbers=() number add_more

    while true; do
        number="$(prompt_var "Phone number to allow (E.164, e.g. +15551234567) — leave blank to allow all senders")"
        if [[ -n "$number" ]]; then
            numbers+=("$number")
        elif [[ "${#numbers[@]}" -eq 0 ]]; then
            break
        fi

        add_more="$(prompt_var "Add another number? (y/n)" "n")"
        [[ "$add_more" =~ ^[Yy] ]] || break
    done

    local IFS=,
    echo "${numbers[*]}"
}

write_env_file() {
    log "Configuring environment variables..."

    local twilio_auth_token twilio_phone_number allowed_phone_numbers
    local flask_host flask_port
    local smee_url target_url webhook_forwarding_url
    local propresenter_host propresenter_port propresenter_message_name propresenter_token_name

    twilio_auth_token="$(prompt_secret "Twilio Auth Token")"
    [[ -n "$twilio_auth_token" ]] || die "Twilio Auth Token is required."
    twilio_phone_number="$(prompt_var "Twilio phone number (e.g. +15551234567)")"
    allowed_phone_numbers="$(prompt_allowed_numbers)"

    flask_host="$(prompt_var "Flask host" "0.0.0.0")"
    flask_port="$(prompt_var "Flask port" "5000")"

    smee_url="$(prompt_var "Public webhook URL Twilio will call (Smee.io channel, e.g. https://smee.io/xxxx)")"
    [[ -n "$smee_url" ]] || die "A public webhook URL is required."
    webhook_forwarding_url="$smee_url"
    target_url="$(prompt_var "Local URL Smee forwards to" "http://localhost:${flask_port}/sms")"

    propresenter_host="$(prompt_var "ProPresenter host" "localhost")"
    propresenter_port="$(prompt_var "ProPresenter port" "1025")"
    propresenter_message_name="$(prompt_var "ProPresenter message name" "SMS Notification")"
    propresenter_token_name="$(prompt_var "ProPresenter token name" "message")"

    local env_file="$INSTALL_DIR/.env"
    umask 077
    cat >"$env_file" <<EOF
TWILIO_AUTH_TOKEN=$twilio_auth_token
TWILIO_PHONE_NUMBER=$twilio_phone_number
ALLOWED_PHONE_NUMBERS=$allowed_phone_numbers

FLASK_HOST=$flask_host
FLASK_PORT=$flask_port

SMEE_URL=$smee_url
TARGET_URL=$target_url
WEBHOOK_FORWARDING_URL=$webhook_forwarding_url

PROPRESENTER_HOST=$propresenter_host
PROPRESENTER_PORT=$propresenter_port
PROPRESENTER_MESSAGE_NAME=$propresenter_message_name
PROPRESENTER_TOKEN_NAME=$propresenter_token_name

VALIDATE_TWILIO_SIGNATURE=true
EOF
    chmod 600 "$env_file"
    log ".env written to $env_file (owner read/write only)."
}

# ---------------------------------------------------------------------------
# LaunchAgent
# ---------------------------------------------------------------------------

install_launch_agent() {
    log "Installing LaunchAgent ($LAUNCH_AGENT_LABEL)..."
    mkdir -p "$HOME/Library/LaunchAgents"

    cat >"$LAUNCH_AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCH_AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BIN_LINK}</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${INSTALL_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${INSTALL_DIR}/logs/of-notifier.log</string>
    <key>StandardErrorPath</key>
    <string>${INSTALL_DIR}/logs/of-notifier.err.log</string>
</dict>
</plist>
EOF

    local uid
    uid="$(id -u)"
    launchctl bootout "gui/$uid" "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
    launchctl bootstrap "gui/$uid" "$LAUNCH_AGENT_PLIST"
    launchctl enable "gui/$uid/$LAUNCH_AGENT_LABEL"
    log "LaunchAgent installed and started."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    require_macos
    require_not_root

    install_xcode_clt
    install_homebrew
    ensure_brew_shellenv
    install_uv
    install_node
    install_python

    install_app_files
    install_wrapper
    sync_and_build
    write_env_file
    install_launch_agent

    cat <<EOF

==> of-notifier installed.

  App directory:   $INSTALL_DIR
  Global command:  of-notifier
  Logs:            $INSTALL_DIR/logs/
  Service status:  launchctl print gui/$(id -u)/$LAUNCH_AGENT_LABEL
  Restart service: launchctl kickstart -k gui/$(id -u)/$LAUNCH_AGENT_LABEL

The service is already running and will start automatically at login.
EOF
}

main "$@"
