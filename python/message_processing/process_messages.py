# process_messages.py

import asyncio
from langchain_openai import ChatOpenAI

from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.nats.nats_consumer import NATSConsumer
from modules.environment.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD, NATS_URL, NKEYSEED, USE_QUEUE_GROUP, OPENAI_API_KEY
from modules.messages.message_processor import MessageProcessor
from modules.langchain.tools import create_supervisor, initialize_graph, create_tools


async def main():
    neo4j_adapter = Neo4jAdapter(uri=NEO4J_URI, username=NEO4J_USERNAME, password=NEO4J_PASSWORD)

    # Connect to Neo4j
    await neo4j_adapter.connect()

    # Initialize the LLM
    llm = ChatOpenAI(temperature=0, openai_api_key=OPENAI_API_KEY, model_name="gpt-4-0125-preview")
    tools = create_tools(neo4j_adapter)  # Ensure this returns a dictionary of tools

    # Initialize the supervisor chain and graph
    supervisor_chain = create_supervisor(llm)  # Ensure this function is defined and imported
    graph = initialize_graph(llm, tools, supervisor_chain)

    message_processor = MessageProcessor(neo4j_adapter=neo4j_adapter, graph=graph)

    consumer = NATSConsumer(
        nats_url=NATS_URL,
        nkeyseed=NKEYSEED,
        subjects=["irc"],
        durable_name="threadr-irc",
        stream_name="message_processing",
        use_queue_group=USE_QUEUE_GROUP,
        neo4j_adapter=neo4j_adapter,
        message_processor=message_processor.process_message
    )
    await consumer.run()

    # Cleanup
    await neo4j_adapter.close()

if __name__ == '__main__':
    asyncio.run(main())
