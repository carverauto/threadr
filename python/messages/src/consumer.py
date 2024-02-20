import asyncio
import json
from nats.aio.client import Client as NATS
from nats.aio.errors import ErrConnectionClosed, ErrTimeout, ErrNoServers
from .cloudevents_processor import process_cloudevent
from configs.settings import NATS_URL, NKEYSEED, USE_QUEUE_GROUP
from .neo4j_adapter import Neo4jAdapter


class NATSConsumer:
    def __init__(self, nats_url=NATS_URL, nkeyseed=NKEYSEED,
                 subjects=["irc"], durable_name="threadr-irc",
                 stream_name="messages", use_queue_group=USE_QUEUE_GROUP,
                 neo4j_adapter=None):
        self.nats_url = nats_url
        self.nkeyseed = nkeyseed
        self.subjects = subjects
        self.durable_name = durable_name
        self.stream_name = stream_name
        self.use_queue_group = use_queue_group
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
        subject = msg.subject
        data = msg.data.decode()
        print(f"Received a message on '{subject}': {data}")

        try:
            data_dict = json.loads(data)
            if self.neo4j_adapter is not None:
                await process_cloudevent(data_dict, self.neo4j_adapter)
            else:
                print("Neo4j adapter not initialized.")
        except Exception as e:
            print(f"Error processing message: {e}")

        # Correctly acknowledge the message in JetStream context
        await msg.ack()

    async def subscribe(self):
        await self.connect()
        if self.js:
            print("Subscribing to subjects...")
            print(f"Durable name: {self.durable_name}")
            print(f"Stream name: {self.stream_name}")
            print(f"Use queue group: {self.use_queue_group}")
            print(f"Subjects: {self.subjects}")
            print(f"JetStream context: {self.js}")

            # Ensure correct subscription for durable and possibly queue group
            # Note: Adjusted to explicitly handle queue groups if needed
            for subject in self.subjects:
                await self.js.subscribe(subject=subject, 
                                        durable=self.durable_name, 
                                        queue=self.durable_name if self.use_queue_group else None,
                                        cb=self.message_handler)
            print("Subscribed to subjects...")
        else:
            print("JetStream context not initialized. Subscription failed.")

    async def run(self):
        await self.subscribe()
        while True:
            await asyncio.sleep(1)


async def main():
    neo4j_adapter = Neo4jAdapter(uri="bolt://localhost:7687", username="neo4j",
                                 password="your_password")
    await neo4j_adapter.connect()
    consumer = NATSConsumer(neo4j_adapter=neo4j_adapter)
    await consumer.run()

if __name__ == '__main__':
    asyncio.run(main())
