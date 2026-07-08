# message-forwarder

Forwards webhook traffic from a [Smee.io](https://smee.io) channel to a local URL.

## Setup

```bash
npm install
```

## Usage

```bash
SMEE_URL=https://smee.io/your-channel TARGET_URL=http://localhost:3000/webhook npm start
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SMEE_URL` | Yes | Smee.io channel URL to subscribe to |
| `TARGET_URL` | Yes | Local URL to forward incoming webhook events to |

## Getting a Smee URL

Visit [smee.io](https://smee.io) and click **Start a new channel** to get a unique URL.

## Stopping

Press `Ctrl+C` to stop the forwarder.
