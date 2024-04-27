# process_messages.py

import os
import asyncio

from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.environment.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD, NATS_URL, NKEYSEED, USE_QUEUE_GROUP, \
    OPENAI_API_KEY
from modules.messages.message_processor import MessageProcessor
from modules.nats.nats_manager import NATSManager
from modules.nats.nats_consumer import NATSConsumer
from modules.nats.nats_producer import NATSProducer

# Warning control
import warnings

warnings.filterwarnings("ignore")

# Optional, add tracing in LangSmith
os.environ["LANGCHAIN_TRACING_V2"] = "true"
os.environ["LANGCHAIN_PROJECT"] = "process_messages"


async def main():
    """
    Main function to process messages.
    :return:
    """
    neo4j_adapter = Neo4jAdapter(uri=NEO4J_URI, username=NEO4J_USERNAME, password=NEO4J_PASSWORD)

    # Connect to Neo4j
    await neo4j_adapter.connect()

    nats_manager = NATSManager(NATS_URL, NKEYSEED)
    await nats_manager.connect()

    # Initialize the producer
    producer = NATSProducer(nats_manager)

    # Initialize the LLM
    # llm = ChatOpenAI(temperature=0, openai_api_key=OPENAI_API_KEY, model_name="gpt-4-0125-preview")

    message_processor = MessageProcessor(neo4j_adapter=neo4j_adapter, producer=producer)

    consumer = NATSConsumer(
        nats_manager=nats_manager,
        subjects=["chat"],
        durable_name="threadr-chat",
        stream_name="message_processing",
        use_queue_group=USE_QUEUE_GROUP,
        #neo4j_adapter=neo4j_adapter,
        message_processor=message_processor.process_message
    )
    print("Starting consumer...")
    await consumer.run()

    # Cleanup
    await neo4j_adapter.close()


if __name__ == '__main__':
    asyncio.run(main())
