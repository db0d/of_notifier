"""ProPresenter local HTTP API client for updating and triggering messages."""

import logging
import os
import requests

logger = logging.getLogger(__name__)

BASE_URL = "http://{host}:{port}/v1".format(
    host=os.getenv("PROPRESENTER_HOST", "localhost"),
    port=os.getenv("PROPRESENTER_PORT", "1025"),
)

logger.debug("ProPresenter base URL: %s", BASE_URL)


def _check(resp: requests.Response) -> requests.Response:
    if not resp.ok:
        logger.error(
            "%s %s → %s  body=%s",
            resp.request.method,
            resp.url,
            resp.status_code,
            resp.text,
        )
    resp.raise_for_status()
    return resp


def _get(path: str) -> requests.Response:
    url = f"{BASE_URL}{path}"
    logger.debug("GET %s", url)
    resp = requests.get(url, timeout=5)
    logger.debug("GET %s → %s", url, resp.status_code)
    return _check(resp)


def _put(path: str, payload: dict) -> requests.Response:
    url = f"{BASE_URL}{path}"
    logger.debug("PUT %s  payload=%s", url, payload)
    resp = requests.put(url, json=payload, timeout=5)
    logger.debug("PUT %s → %s", url, resp.status_code)
    return _check(resp)


def _post(path: str, payload: list | dict | None = None) -> requests.Response:
    url = f"{BASE_URL}{path}"
    logger.debug("POST %s  payload=%s", url, payload)
    resp = requests.post(url, json=payload, timeout=5)
    logger.debug("POST %s → %s", url, resp.status_code)
    return _check(resp)


def find_message_by_name(name: str) -> dict | None:
    """Return the first message whose name matches (case-insensitive)."""
    logger.debug("Fetching all ProPresenter messages.")
    messages = _get("/messages").json()
    logger.debug("Received %d messages from ProPresenter.", len(messages))
    for msg in messages:
        msg_name = msg.get("id", {}).get("name", "")
        logger.debug("  Checking message name %r against %r.", msg_name, name)
        if msg_name.lower() == name.lower():
            logger.debug("Match found: %s", msg)
            return msg
    logger.debug("No message matched name %r.", name)
    return None


def update_and_trigger(message_id: str, token_name: str, text: str) -> None:
    """
    Set the named token in a message to `text`, then trigger it.

    ProPresenter messages use a token list like:
        {"name": "tokens", "tokens": [{"name": "message", "text": {"text": "..."}}]}
    """
    _get(f"/message/{message_id}/clear") # Clear the message before updating it, to avoid leftover tokens from previous updates.
    logger.debug("Fetching message id=%s for update.", message_id)
    msg = _get(f"/message/{message_id}").json()
    logger.debug("Current message state: %s", msg)

    updated_tokens = []
    token_found = False
    for token in msg.get("tokens", []):
        t_name = token.get("name", "")
        if t_name.lower() == token_name.lower():
            logger.debug("Updating token %r → %r", t_name, text)
            token["text"] = {"text": text}
            token_found = True
        updated_tokens.append(token)

    if not token_found:
        available = [t.get("name") for t in msg.get("tokens", [])]
        logger.warning(
            "Token %r not found in message %s — available tokens: %s; appending new token.",
            token_name,
            message_id,
            available,
        )
        updated_tokens.append({"name": token_name, "text": {"text": text}})

    msg["tokens"] = updated_tokens
    msg["message"] = f"{text}"
    logger.debug("Putting updated message %s: %s", message_id, msg)
   # _put(f"/message/{message_id}", msg)

    logger.debug("Triggering message %s.", message_id)
    _post(f"/message/{message_id}/trigger", updated_tokens)

    logger.info("Message %s updated (token=%r, text=%r) and triggered.", message_id, token_name, text)
