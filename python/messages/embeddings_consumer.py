import asyncio
from src.neo4j_adapter import Neo4jAdapter
from src.nats_consumer import NATSConsumer
from configs.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD, NATS_URL, NKEYSEED, USE_QUEUE_GROUP
from src.embeddings_processor import EmbeddingsProcessor


async def main():
    neo4j_adapter = Neo4jAdapter(uri=NEO4J_URI, username=NEO4J_USERNAME, password=NEO4J_PASSWORD)

    # Connect to Neo4j
    await neo4j_adapter.connect()

    embeddings_processor = EmbeddingsProcessor(neo4j_adapter=neo4j_adapter)

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
