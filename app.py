"""Twilio SMS → ProPresenter message bridge (webhook mode)."""

import logging
import os

from dotenv import load_dotenv

load_dotenv()

from flask import Flask, request, abort
from twilio.request_validator import RequestValidator
from twilio.twiml.messaging_response import MessagingResponse

import propresenter
import re

logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

TWILIO_AUTH_TOKEN = os.environ["TWILIO_AUTH_TOKEN"]
PROPRESENTER_MESSAGE_NAME = os.getenv("PROPRESENTER_MESSAGE_NAME", "SMS Notification")
PROPRESENTER_TOKEN_NAME = os.getenv("PROPRESENTER_TOKEN_NAME", "message")
VALIDATE_SIGNATURE = os.getenv("VALIDATE_TWILIO_SIGNATURE", "true").lower() == "true"
ALLOWED_PHONE_NUMBERS = {
    number.strip()
    for number in os.getenv("ALLOWED_PHONE_NUMBERS", "").split(",")
    if number.strip()
}
MESSAGE_REGEX = re.compile(os.getenv("MESSAGE_REGEX_PATTERN", ".*"))

logger.debug(
    "Config loaded — PROPRESENTER_MESSAGE_NAME=%r  PROPRESENTER_TOKEN_NAME=%r  "
    "VALIDATE_SIGNATURE=%s  ALLOWED_PHONE_NUMBERS=%s  MESSAGE_REGEX_PATTERN=%r",
    PROPRESENTER_MESSAGE_NAME,
    PROPRESENTER_TOKEN_NAME,
    VALIDATE_SIGNATURE,
    f"(configured: {len(ALLOWED_PHONE_NUMBERS)} entries)" if ALLOWED_PHONE_NUMBERS else "(none — all senders allowed)",
    MESSAGE_REGEX.pattern,
)

_validator = RequestValidator(TWILIO_AUTH_TOKEN)


def _validate_twilio_request(sms_request) -> None:
    """Abort with 403 if the request didn't come from Twilio."""
    if not VALIDATE_SIGNATURE:
        logger.debug("Signature validation disabled — skipping.")
        return
    signature = sms_request.headers.get("X-Twilio-Signature", "")
    url = os.getenv("WEBHOOK_FORWARDING_URL", sms_request.url)
    params = sms_request.json
    logger.debug(
        "Validating Twilio signature.\n"
        "  URL:       %s\n"
        "  Signature: %s\n"
        "  Params:    %s",
        url,
        signature,
        params,
    )
    if not _validator.validate(url, params, signature):
        logger.warning(
            "Invalid Twilio signature — rejecting request.\n"
            "  URL:       %s\n"
            "  Signature: %s\n"
            "  Params:    %s",
            url,
            signature,
            params,
        )
        abort(403)
    logger.debug("Twilio signature valid.")


def _validate_sender(sender: str) -> None:
    """Abort with 403 if the sender isn't on the configured allow list."""
    if not ALLOWED_PHONE_NUMBERS:
        logger.debug("No ALLOWED_PHONE_NUMBERS configured — skipping sender check.")
        return
    if sender not in ALLOWED_PHONE_NUMBERS:
        logger.warning("SMS from %s rejected — not in ALLOWED_PHONE_NUMBERS.", sender)
        abort(403)
    logger.debug("Sender %s is on the allow list.", sender)


@app.route("/sms", methods=["POST"])
def sms_webhook():
    logger.debug(
        "POST /sms received — headers: %s",
        dict(request.headers),
    )
    logger.debug(request.json)
    _validate_twilio_request(request)

    sender = request.json.get("From", "unknown")
    body = request.json.get("Body", "").strip()

    _validate_sender(sender)

    if not MESSAGE_REGEX.fullmatch(body):
        logger.info("SMS from %s does not match MESSAGE_REGEX_PATTERN: %r", sender, body)
        return _twiml_reply("")
    logger.debug("Form data: %s", request.json)
    logger.info("SMS from %s: %r", sender, body)

    if not body:
        logger.info("Empty body — nothing to display.")
        return _twiml_reply("")

    try:
        logger.debug("Looking up ProPresenter message %r.", PROPRESENTER_MESSAGE_NAME)
        message = propresenter.find_message_by_name(PROPRESENTER_MESSAGE_NAME)
        if message is None:
            logger.error("ProPresenter message %r not found.", PROPRESENTER_MESSAGE_NAME)
            return _twiml_reply("")

        logger.debug("Found message: id=%s", message["id"]["uuid"])
        propresenter.update_and_trigger(
            message_id=message["id"]["uuid"],
            token_name=PROPRESENTER_TOKEN_NAME,
            text=body,
        )
        logger.info("Successfully forwarded SMS to ProPresenter.")
    except Exception:
        logger.exception("Failed to update ProPresenter message.")

    return _twiml_reply("")


def _twiml_reply(text: str) -> str:
    resp = MessagingResponse()
    if text:
        resp.message(text)
    twiml = str(resp)
    logger.debug("Returning TwiML: %r", twiml)
    return twiml, 200, {"Content-Type": "application/json"}


if __name__ == "__main__":
    host = os.getenv("FLASK_HOST", "127.0.0.1")
    port = int(os.getenv("FLASK_PORT", "5000"))
    logger.info("Starting webhook server on %s:%s", host, port)
    app.run(host=host, port=port)
