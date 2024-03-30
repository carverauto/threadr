# modules/nats/publish_message.py
from datetime import datetime
from nats.aio.client import Client as NATS
from modules.environment.settings import NATS_URL, NATS_NKEYSEED
import json


async def publish_message_to_jetstream(subject, stream, message_id,
                                       message_content, channel):
    """
    Publishes message details to a NATS Jetstream queue for asynchronous processing.

    Parameters:
    - nats_url: URL of the NATS server
    - subject: NATS subject to publish the message to
    - message_id: The ID of the message in Neo4j
    - message_content: The content of the message being processed
    """
    nc = NATS()

    # error_cb:
    async def error_cb(e):
        print(f"Error: {e}")

    await nc.connect(NATS_URL, nkeys_seed_str=NATS_NKEYSEED,
                     error_cb=error_cb,
                     reconnect_time_wait=10)
    
    js = nc.jetstream()

    await js.add_stream(name=stream, subjects=[subject])

    # Ensure message_content is a dict that can be directly serialized
    #if isinstance(message_content, str):
    #    # Attempt to parse the string as JSON; this assumes message_content is a JSON string
    #    try:
    #        message_content = json.loads(message_content)
    #    except json.JSONDecodeError:
    #        # Handle cases where message_content is not a valid JSON string
    #        print("message_content is not valid JSON. Publishing as a plain string.")
    #        # Optionally, you could choose to not publish at all or handle differently

    # Construct the message data according to the CommandResult structure
    message_data = {
        "message_id": message_id,
        "content": {
            "response": message_content,
            "channel": channel,
            "timestamp": datetime.now().isoformat()
        }
    }

    await js.publish(subject, json.dumps(message_data).encode())
    print(f"Published message ID {message_id} to Jetstream subject '{subject}'.")
    await nc.close()
