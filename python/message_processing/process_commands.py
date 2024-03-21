# process_commands.py

import asyncio
from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.nats.nats_consumer import NATSConsumer
from modules.environment.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD, NATS_URL, NKEYSEED, USE_QUEUE_GROUP
from modules.messages.message_processor import MessageProcessor


async def main():
    neo4j_adapter = Neo4jAdapter(uri=NEO4J_URI, username=NEO4J_USERNAME, password=NEO4J_PASSWORD)

    # Connect to Neo4j
    await neo4j_adapter.connect()

    message_processor = MessageProcessor(neo4j_adapter=neo4j_adapter)

    consumer = NATSConsumer(
        nats_url=NATS_URL,
        nkeyseed=NKEYSEED,
        subjects=["incoming"],
        durable_name="threadr-irc-commands",
        stream_name="commands",
        use_queue_group=USE_QUEUE_GROUP,
        neo4j_adapter=neo4j_adapter,
        message_processor=message_processor.process_commands
    )
    await consumer.run()

    # Cleanup
    await neo4j_adapter.close()


if __name__ == '__main__':
    asyncio.run(main())
