"""Entry points for running and preparing the of-notifier service."""

import os
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
FORWARDER_DIR = ROOT / "message_forwarder"


def start() -> None:
    """Start the Flask webhook app, then the Smee message forwarder, in parallel."""
    load_dotenv(ROOT / ".env")
    processes = []

    print("Starting Flask app...")
    processes.append(
        subprocess.Popen([sys.executable, "app.py"], cwd=ROOT, env=os.environ.copy())
    )

    print("Starting message forwarder...")
    processes.append(
        subprocess.Popen(["npm", "start"], cwd=FORWARDER_DIR, env=os.environ.copy())
    )

    try:
        os.wait()
    except KeyboardInterrupt:
        pass
    finally:
        for proc in processes:
            if proc.poll() is None:
                proc.terminate()


def build() -> None:
    """Sync Python dependencies and install the message forwarder's npm dependencies."""
    print("Syncing Python dependencies...")
    subprocess.run(["uv", "sync"], cwd=ROOT, check=True)

    print("Installing message forwarder dependencies...")
    subprocess.run(["npm", "install", "--ignore-scripts"], cwd=FORWARDER_DIR, check=True)

    print("Build complete.")
