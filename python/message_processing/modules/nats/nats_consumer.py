# modules/nats/nats_consumer.py

import asyncio
from nats.aio.errors import ErrConnectionClosed, ErrTimeout, ErrNoServers
from modules.environment.settings import NATS_URL, NKEYSEED, USE_QUEUE_GROUP
from modules.nats.base_nats import BaseNATS
from typing import Callable


class NATSConsumer(BaseNATS):
    def __init__(self, subjects=["irc"], durable_name="threadr-irc",
                 stream_name="messages", use_queue_group=False,
                 message_processor: Callable[[str], None] = None, **kwargs):
        super().__init__(**kwargs)
        self.subjects = subjects
        self.durable_name = durable_name
        self.stream_name = stream_name
        self.use_queue_group = use_queue_group
        self.message_processor = message_processor



    @property
    def client(self):
        return self.nc

    @property
    def jetstream(self):
        return self.js

    async def stop(self):
        # Close the NATS connection
        await self.nc.close()
        print("NATS connection closed.")

    async def message_handler(self, msg):
        if self.message_processor:
            await self.message_processor(msg)
        else:
            print("No message processor defined.")

    async def subscribe(self):
        await self.connect()
        if self.js:
            print("Subscribing to subjects...")
            print(f"Durable name: {self.durable_name}")
            print(f"Stream name: {self.stream_name}")
            print(f"Use queue group: {self.use_queue_group}")
            print(f"Subjects: {self.subjects}")

            # Ensure correct subscription for durable and possibly queue group
            # Note: Adjusted to explicitly handle queue groups if needed
            for subject in self.subjects:
                if self.use_queue_group:
                    await self.js.subscribe(subject=subject, durable=self.durable_name, queue=self.durable_name, cb=self.message_handler)
                else:
                    await self.js.subscribe(subject=subject, durable=self.durable_name, cb=self.message_handler)
            print("Subscribed to subjects...")
        else:
            print("JetStream context not initialized. Subscription failed.")

    async def run(self):
        try:
            await self.subscribe()
            while True:
                await asyncio.sleep(1)
        except KeyboardInterrupt:
            print("Keyboard interrupt received. Shutting down gracefully.")
            await self.stop()
