# modules/nats/nats_producer.py

from .base_nats import BaseNATS
import json

class NATSProducer(BaseNATS):
    async def publish_message(self, subject, message_data):
        await self.connect()
        if self.js:
            await self.js.publish(subject, json.dumps(message_data).encode())
            print(f"Published message to Jetstream subject '{subject}'.")
        else:
            print("JetStream context not initialized. Publish failed.")
