# of_kids_notifier

A small service that listens for incoming SMS messages on a Twilio virtual
phone number and forwards them into a ProPresenter message (lower third /
graphic) via the ProPresenter local HTTP API.

Twilio POSTs each incoming message to a public [Smee.io](https://smee.io)
channel, which the bundled message forwarder relays to the local `/sms`
endpoint — no need to run your own tunnel (e.g. ngrok).

## Requirements

- Python 3.14 (managed automatically by [uv](https://docs.astral.sh/uv/))
- [uv](https://docs.astral.sh/uv/getting-started/installation/)
- Node.js + npm (for the message forwarder)
- ProPresenter 7 running locally with the Network API enabled
- A Twilio account with a virtual phone number
- A [Smee.io](https://smee.io) channel
- Message token added to the ProPresenter message template (e.g. `message`)

## Setup

### macOS: automated install

```bash
./install/install.sh
```

Installs all dependencies, syncs the project, prompts for your `.env`
values, and registers the service as a login LaunchAgent so it starts
automatically and restarts if it crashes. See [install/README.md](install/README.md)
for details and service management commands.

### Manual setup

#### 1. Sync dependencies

```bash
uv run build
```

Syncs Python dependencies (and provisions Python 3.14 if needed) and
installs the message forwarder's npm dependencies.

#### 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env` with your values:

| Variable | Description |
|---|---|
| `TWILIO_AUTH_TOKEN` | Found at [twilio.com/console](https://twilio.com/console) |
| `TWILIO_PHONE_NUMBER` | Your Twilio virtual number, e.g. `+15551234567` |
| `SMEE_URL` | Your Smee.io channel URL — this is what Twilio calls |
| `TARGET_URL` | Local URL Smee forwards to (default: `http://localhost:5000/sms`) |
| `WEBHOOK_FORWARDING_URL` | URL used to validate the Twilio signature — usually the same as `SMEE_URL` |
| `PROPRESENTER_HOST` | Host running ProPresenter (default: `localhost`) |
| `PROPRESENTER_PORT` | ProPresenter API port (default: `1025`) |
| `PROPRESENTER_MESSAGE_NAME` | Exact name of the ProPresenter message to update |
| `PROPRESENTER_TOKEN_NAME` | Token name in the message template (default: `message`) |
| `FLASK_HOST` | Interface to bind (default: `0.0.0.0`) |
| `FLASK_PORT` | Port to listen on (default: `5000`) |
| `VALIDATE_TWILIO_SIGNATURE` | Set to `false` only for local testing (default: `true`) |

#### 3. Enable the ProPresenter Network API

In ProPresenter: **Preferences → Network → Enable Network API**

Note the port (default 1025) and make sure it matches `PROPRESENTER_PORT` in
your `.env`.

#### 4. Create a message in ProPresenter

Create a message template with at least one token. For example, a message
named **"SMS Notification"** with a token called `message`. The token name
must match `PROPRESENTER_TOKEN_NAME` in your `.env`.

#### 5. Get a Smee channel

Visit [smee.io](https://smee.io) and click **Start a new channel**. Put the
URL it gives you in both `SMEE_URL` and `WEBHOOK_FORWARDING_URL` in `.env`.

#### 6. Configure your Twilio number

1. Go to [twilio.com/console](https://twilio.com/console) → Phone Numbers →
   Manage → your number
2. Under **Messaging**, set **"A message comes in"** to your `SMEE_URL`.
   Method: `HTTP POST`
3. Save

#### 7. Run the service

```bash
uv run start
```

Starts the Flask webhook server, then the Smee message forwarder, in
parallel. Press `Ctrl+C` to stop both.

---

## Project structure

```
of_kids_notifier/
├── app.py                    # Flask webhook server
├── propresenter.py           # ProPresenter local API client
├── pyproject.toml            # Project metadata, dependencies, uv scripts
├── uv.lock
├── .env.example              # Config template
├── utils/
│   └── cli.py                 # `uv run start` / `uv run build` entry points
├── message_forwarder/         # Node/Smee client that relays Twilio's webhook locally
│   ├── index.js
│   ├── package.json
│   └── README.md
├── install/                   # macOS installer (dependencies + LaunchAgent service)
│   ├── install.sh
│   └── README.md
└── README.md
```
