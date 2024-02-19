import asyncio
import json
import nats
from .cloudevents_processor import process_cloudevent
from configs.settings import NATS_URL


class NATSConsumer:
    def __init__(self, nats_url=NATS_URL):
        self.nats_url = nats_url
        self.nc = None
        self.js = None

    async def connect(self):
        self.nc = await nats.connect(self.nats_url)
        self.js = self.nc.jetstream()

    async def message_handler(self, msg):
        subject = msg.subject
        data = msg.data.decode()
        print(f"Received a message on '{subject}': {data}")
        
        # Assuming data is JSON, convert it to a dictionary
        data_dict = json.loads(data)

        # Process the message using the cloudevents processor
        process_cloudevent(data_dict)

        # Acknowledge the message
        await msg.ack()

    async def subscribe(self, subject, durable_name):
        await self.js.subscribe(
            subject, durable=durable_name, cb=self.message_handler
        )

    async def run(self):
        await self.connect()
        # Setup your subscription
        # Example: await self.subscribe("foo", "my_consumer")

        print("Listening for messages...")


async def main():
    consumer = NATSConsumer()
    await consumer.run()
    await asyncio.Future()  # Keeps the script running

if __name__ == '__main__':
    asyncio.run(main())
