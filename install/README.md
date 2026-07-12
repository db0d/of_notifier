# install/

macOS installer for of-notifier. Sets up all dependencies, installs the app
as a global command, and registers it as a login service.

## Usage

Run as your normal user — **not** with `sudo`. The script calls `sudo`
itself for the specific steps that need elevated permissions.

```bash
./install/install.sh
```

You'll be prompted for your password (for `sudo` steps and Homebrew, if it
needs to be installed) and for the service's environment variables.

## What it does

1. **Dependencies** — checks for and installs, in order:
   - Xcode Command Line Tools (via Apple's own signed installer)
   - Homebrew (via the official bootstrap script, if not already installed)
   - `uv` and `node`/`npm` (via `brew install`, which verifies checksums and
     bottle signatures internally)
   - Python 3.14 (via `uv python install 3.14` — uv downloads and
     hash-verifies its own managed Python builds)
2. **App files** — copies the repo into `/usr/local/opt/of-notifier`
   (excluding `.git`, `.venv`, `node_modules`, `.env`, and `install/`).
3. **Global command** — installs a wrapper at `/usr/local/bin/of-notifier`
   that runs `uv run --project /usr/local/opt/of-notifier start`.
4. **Build** — runs `uv sync` then `uv run build` in the install directory
   (syncs Python deps, installs the message forwarder's npm deps).
5. **Environment** — prompts for the Twilio, Flask, Smee/webhook, and
   ProPresenter settings, then writes `/usr/local/opt/of-notifier/.env`
   with `chmod 600` (owner read/write only).
6. **Service** — installs a per-user LaunchAgent (`local.of-notifier`) with
   `RunAtLoad` + `KeepAlive`, so the service starts at login and restarts
   automatically if it crashes.

## Variables you'll be asked for

| Variable | Description |
|---|---|
| `TWILIO_AUTH_TOKEN` | Found at [twilio.com/console](https://twilio.com/console) |
| `TWILIO_PHONE_NUMBER` | Your Twilio virtual number, e.g. `+15551234567` |
| `ALLOWED_PHONE_NUMBERS` | Prompted one number at a time — enter a number, then choose to add another or move on. Leave the first entry blank to allow all senders |
| `FLASK_HOST` / `FLASK_PORT` | Interface/port the webhook server binds to |
| Smee webhook URL | Public URL Twilio calls (a [smee.io](https://smee.io) channel) — used for both `SMEE_URL` and `WEBHOOK_FORWARDING_URL` |
| Local target URL | Where Smee forwards to locally (default `http://localhost:<FLASK_PORT>/sms`) |
| `PROPRESENTER_HOST` / `PROPRESENTER_PORT` | Where ProPresenter's Network API is running |
| `PROPRESENTER_MESSAGE_NAME` / `PROPRESENTER_TOKEN_NAME` | The message and token to update in ProPresenter |

## Managing the service

```bash
# Check status
launchctl print gui/$(id -u)/local.of-notifier

# Restart
launchctl kickstart -k gui/$(id -u)/local.of-notifier

# Stop / unload
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.of-notifier.plist

# Logs
tail -f /usr/local/opt/of-notifier/logs/of-notifier.log
tail -f /usr/local/opt/of-notifier/logs/of-notifier.err.log
```

## Re-running

The installer is idempotent — re-running it skips already-installed
dependencies, re-syncs the app files, re-prompts for the `.env` values, and
re-registers the LaunchAgent.

## Uninstalling

```bash
./install/uninstall.sh
```

Run as your normal user — **not** with `sudo` (it calls `sudo` itself
where needed). This:

1. Stops and removes the LaunchAgent (`local.of-notifier`).
2. Removes the global wrapper command (`/usr/local/bin/of-notifier`).
3. Removes the app directory (`/usr/local/opt/of-notifier`), including the
   `.env` secrets file — after a confirmation prompt, since this step is
   irreversible.

Shared dependencies installed via Homebrew (`uv`, `node`) and the Xcode
Command Line Tools are left in place, since they aren't exclusive to this
app.
