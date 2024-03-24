# process_messages.py

import asyncio
#from langchain.agents import initialize_agent, AgentType
from langchain.agents import AgentExecutor, create_openai_tools_agent
from langchain_community.chat_models import ChatOpenAI
# from langchain.memory import ConversationBufferMemory
from langchain import hub
from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.nats.nats_consumer import NATSConsumer
from modules.environment.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD, NATS_URL, NKEYSEED, USE_QUEUE_GROUP, OPENAI_API_KEY
from modules.messages.message_processor import MessageProcessor
from modules.langchain.tools import create_tools


async def main():
    neo4j_adapter = Neo4jAdapter(uri=NEO4J_URI, username=NEO4J_USERNAME, password=NEO4J_PASSWORD)

    # Connect to Neo4j
    await neo4j_adapter.connect()

    prompt = hub.pull("hwchase17/openai-tools-agent")

    # Initialize the LLM
    llm = ChatOpenAI(temperature=0, openai_api_key=OPENAI_API_KEY, model_name="gpt-4-0125-preview")

    # Initialize conversation memory
    # memory = ConversationBufferMemory(memory_key="chat_history", return_messages=True)

    # Create tools
    tools = create_tools(neo4j_adapter)

    # Initialize the agent
    # agent = initialize_agent(
    #    tools,
    #    llm,
    #    memory=memory,
    #    agent=AgentType.CHAT_CONVERSATIONAL_REACT_DESCRIPTION,
    #    #agent=AgentType.CHAT_ZERO_SHOT_REACT_DESCRIPTION,
    #    verbose=True,
    #)

    agent = create_openai_tools_agent(llm, tools, prompt)
    agent_executor = AgentExecutor(agent=agent, tools=tools, verbose=True, max_iterations=4,return_only_outputs=True)

    message_processor = MessageProcessor(neo4j_adapter=neo4j_adapter, agent_executor=agent_executor)

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
