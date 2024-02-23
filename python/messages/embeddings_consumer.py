# embeddings_consumer.py

import asyncio
import signal
from src.neo4j_adapter import Neo4jAdapter
from src.nats_consumer import NATSConsumer
from configs.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD, NATS_URL, NKEYSEED, USE_QUEUE_GROUP
from src.embeddings_processor import EmbeddingsProcessor
from src.embeddings import SentenceTransformerEmbedding


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

    embedding_model = SentenceTransformerEmbedding(model_name="sentence-transformers/all-mpnet-base-v2", 
                                                   model_args={}, 
                                                   quantization_config=None)
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
