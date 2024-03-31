# modules/nats/publish_message.py
from datetime import datetime
import json


async def publish_message_to_jetstream(js, subject, message_id,
                                       message_content, channel):
    """
    Publishes message details to a NATS Jetstream queue for asynchronous processing.

    Parameters:
    - js: Jetstream context
    - nats_url: URL of the NATS server
    - subject: NATS subject to publish the message to
    - message_id: The ID of the message in Neo4j
    - message_content: The content of the message being processed
    """
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
