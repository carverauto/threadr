# create_embeddings.py

import asyncio
import signal
from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.nats.nats_consumer import NATSConsumer
from modules.environment.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD, NATS_URL, NKEYSEED, USE_QUEUE_GROUP
from modules.embeddings.embeddings_processor import EmbeddingsProcessor
from modules.embeddings.openai_embeddings import OpenAIEmbedding


async def main():
    neo4j_adapter = Neo4jAdapter(uri=NEO4J_URI, username=NEO4J_USERNAME, password=NEO4J_PASSWORD)

    # Connect to Neo4j
    await neo4j_adapter.connect()

    async def shutdown(signal, loop):
        print(f"Received exit signal {signal.name}...")
        await consumer.stop()
        await neo4j_adapter.close()
        loop.stop()

    loop = asyncio.get_event_loop()
    signals = (signal.SIGHUP, signal.SIGTERM, signal.SIGINT)
    for s in signals:
        loop.add_signal_handler(
            s, lambda s=s: asyncio.create_task(shutdown(s, loop))
        )

    # embedding_model = OpenAIEmbedding(model="text-embedding-3-small", dimensions=1536)
    embedding_model = OpenAIEmbedding()

    embeddings_processor = EmbeddingsProcessor(neo4j_adapter=neo4j_adapter,
                                               embedding_model=embedding_model)

    consumer = NATSConsumer(
        nats_url=NATS_URL,
        nkeyseed=NKEYSEED,
        subjects=["vector_processing"],
        durable_name="threadr-embeddings",
        stream_name="embeddings",
        use_queue_group=USE_QUEUE_GROUP,
        neo4j_adapter=neo4j_adapter,
        message_processor=embeddings_processor.process_embedding
    )
    await consumer.run()

    # Cleanup
    await neo4j_adapter.close()

if __name__ == '__main__':
    asyncio.run(main())
