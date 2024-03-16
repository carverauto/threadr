# publish_message.py

from nats.aio.client import Client as NATS
from modules.environment.settings import NATS_URL, NATS_NKEYSEED
import json


async def publish_message_to_jetstream(subject, stream, message_id, 
                                       message_content):
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
    
    # error_cb, closed_cb, and disconnected_cb are optional callbacks to handle errors, closed connections, and disconnections

    # Assuming the JetStream context is already set up and the stream exists
    js = nc.jetstream()

    await js.add_stream(name=stream, subjects=[subject])

    message_data = {
        "message_id": message_id,
        "content": message_content
    }

    message_json = json.dumps(message_data)  # Serialize to JSON string

    await js.publish(subject, message_json.encode())

    print(f"Published message ID {message_id} to Jetstream subject '{subject}'.")

    # Gracefully close the connection.
    await nc.close()
