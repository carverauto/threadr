# create_embeddings.py

import asyncio
from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.environment.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD, NATS_URL, NKEYSEED, USE_QUEUE_GROUP
from modules.embeddings.embeddings_processor import EmbeddingsProcessor
from modules.embeddings.openai_embeddings import OpenAIEmbedding

from modules.nats.nats_manager import NATSManager
from modules.nats.nats_consumer import NATSConsumer


async def main():
    """
    Main function to process embeddings.
    :return:
    """
    print("Starting embeddings processor...")
    neo4j_adapter = Neo4jAdapter(uri=NEO4J_URI, username=NEO4J_USERNAME, password=NEO4J_PASSWORD)

    # Connect to Neo4j
    await neo4j_adapter.connect()

    nats_manager = NATSManager(NATS_URL, NKEYSEED)
    await nats_manager.connect()

    # embedding_model = OpenAIEmbedding(model="text-embedding-3-small", dimensions=1536)
    embedding_model = OpenAIEmbedding()

    embeddings_processor = EmbeddingsProcessor(neo4j_adapter=neo4j_adapter,
                                               embedding_model=embedding_model)

    consumer = NATSConsumer(
        nats_manager=nats_manager,
        subjects=["vector_processing"],
        durable_name="threadr-embeddings",
        stream_name="embeddings",
        use_queue_group=USE_QUEUE_GROUP,
        #neo4j_adapter=neo4j_adapter,
        message_processor=embeddings_processor.process_embedding
    )
    print("Starting consumer...")
    await consumer.run()

    # Cleanup
    await neo4j_adapter.close()


if __name__ == '__main__':
    asyncio.run(main())
