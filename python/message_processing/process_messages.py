# process_messages.py

import os
import asyncio
from langchain_openai import ChatOpenAI

from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.nats.nats_consumer import NATSConsumer
from modules.environment.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD, NATS_URL, NKEYSEED, USE_QUEUE_GROUP, OPENAI_API_KEY
from modules.messages.message_processor import MessageProcessor
from modules.langchain.langchain import create_supervisor
from modules.langchain.langgraph import initialize_graph
from modules.langchain.tools import create_tools
from modules.langchain.cypherquery import CypherQueryTool, to_openai_function
from langchain import hub
from langchain.agents import create_openai_functions_agent



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

    # Initialize the LLM
    llm = ChatOpenAI(temperature=0, openai_api_key=OPENAI_API_KEY, model_name="gpt-4-0125-preview")
    # Get the prompt to use - you can modify this!
    prompt = hub.pull("hwchase17/openai-functions-agent")

    tools = create_tools(neo4j_adapter)
    cypher_query_tool = tools['CypherQuery']
    openai_function = to_openai_function(cypher_query_tool)

    # Construct the OpenAI Functions agent
    agent_runnable = create_openai_functions_agent(llm, [openai_function], prompt)

    # Initialize the supervisor chain and graph
    supervisor_chain = create_supervisor(llm)  # Ensure this function is defined and imported
    graph = initialize_graph(llm, tools, supervisor_chain,agent_runnable)

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
