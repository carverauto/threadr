import asyncio
from src.consumer import NATSConsumer


async def main():
    consumer = NATSConsumer()
    await consumer.run()

if __name__ == '__main__':
    asyncio.run(main())
