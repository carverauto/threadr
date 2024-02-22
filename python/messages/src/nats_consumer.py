import asyncio
from nats.aio.client import Client as NATS
from nats.aio.errors import ErrConnectionClosed, ErrTimeout, ErrNoServers
from configs.settings import NATS_URL, NKEYSEED, USE_QUEUE_GROUP
from typing import Callable


class NATSConsumer:
    def __init__(self, nats_url=NATS_URL, nkeyseed=NKEYSEED,
                 subjects=["irc"], durable_name="threadr-irc",
                 stream_name="messages", use_queue_group=USE_QUEUE_GROUP,
                 neo4j_adapter=None,
                 message_processor: Callable[[str], None] = None):
        self.nats_url = nats_url
        self.nkeyseed = nkeyseed
        self.subjects = subjects
        self.durable_name = durable_name
        self.stream_name = stream_name
        self.use_queue_group = use_queue_group
        self.message_processor = message_processor
        self.nc = NATS()
        self.neo4j_adapter = neo4j_adapter

    async def connect(self):
        try:
            await self.nc.connect(servers=[self.nats_url], nkeys_seed_str=self.nkeyseed)
            self.js = self.nc.jetstream()  # Corrected: Removed await
            print(f"Connected to NATS at {self.nats_url}...")
            print("JetStream context initialized...")
        except ErrNoServers as e:
            print(f"Could not connect to any server: {e}")
        except ErrConnectionClosed as e:
            print(f"Connection to NATS is closed: {e}")
        except ErrTimeout as e:
            print(f"A timeout occurred when trying to connect: {e}")
        except Exception as e:
            print(f"An error occurred during NATS connection: {e}")

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
        await self.subscribe()
        while True:
            await asyncio.sleep(1)
