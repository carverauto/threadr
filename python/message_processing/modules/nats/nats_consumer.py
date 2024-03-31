# modules/nats/nats_consumer.py

import asyncio
from typing import Callable


class NATSConsumer:
    def __init__(self, nats_manager, subjects, durable_name, stream_name, use_queue_group, message_processor: Callable):
        self.nats_manager = nats_manager
        self.subjects = subjects
        self.durable_name = durable_name
        self.stream_name = stream_name
        self.use_queue_group = use_queue_group
        self.message_processor = message_processor

    async def message_handler(self, msg):
        if self.message_processor:
            await self.message_processor(msg)  # Ensure this is awaited if it's async
        else:
            print("No message processor defined.")

    async def subscribe(self):
        if self.nats_manager.js:
            print("Subscribing to subjects...")
            for subject in self.subjects:
                if self.use_queue_group:
                    await self.nats_manager.js.subscribe(subject=subject, durable=self.durable_name,
                                                         queue=self.durable_name, cb=self.message_handler)
                else:
                    await self.nats_manager.js.subscribe(subject=subject, durable=self.durable_name, cb=self.message_handler)
            print("Subscribed to subjects...")
        else:
            print("JetStream context not initialized. Subscription failed.")

    async def run(self):
        try:
            await self.subscribe()  # Correctly call subscribe method
            while True:
                await asyncio.sleep(1)  # Keep the coroutine alive
        except KeyboardInterrupt:
            print("Keyboard interrupt received. Shutting down gracefully.")
            await self.nats_manager.disconnect()  # Ensure this is the correct method to disconnect
