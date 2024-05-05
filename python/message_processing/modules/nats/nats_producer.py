# modules/natsctl/nats_producer.py

import json
from modules.messages.models import NATSMessage


class NATSProducer:
    """
    A class to handle the publishing of messages to a NATS JetStream queue.
    """
    def __init__(self, nats_manager):
        self.nats_manager = nats_manager

    async def publish_message(self, subject, message_data: NATSMessage):
        """
        Publishes a message to a NATS JetStream queue.
        :param subject:
        :param message_data:
        :return:
        """
        if not self.nats_manager.js:
            print("JetStream context not initialized. Publish failed.")
            return
        try:
            await self.nats_manager.js.publish(subject, json.dumps(message_data).encode())
        except Exception as e:
            print(f"Failed to publish message to Jetstream: {e}")
            return
