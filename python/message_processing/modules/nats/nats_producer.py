# modules/nats/nats_producer.py

import json


class NATSProducer:
    def __init__(self, nats_manager):
        self.nats_manager = nats_manager

    # subject = NATS_EMBEDDING_SUBJECT,
    # message_id = message_id,
    # message_content = message_data.message,
    # channel = message_data.channel

    async def publish_message(self, subject, message_data):
        if not self.nats_manager.js:
            print("JetStream context not initialized. Publish failed.")
            return
        try:
            await self.nats_manager.js.publish(subject, json.dumps(message_data).encode())
        except Exception as e:
            print(f"Failed to publish message to Jetstream: {e}")
            return
        print(f"Published message to Jetstream subject '{subject}'.")
