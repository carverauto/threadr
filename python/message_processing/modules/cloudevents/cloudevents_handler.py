# cloudevents_handler.py
import json

from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import re
from modules.environment.settings import NATS_EMBEDDING_SUBJECT, NATS_EMBEDDING_STREAM, \
    NEO4J_PASSWORD, NEO4J_URI, BOT_NAME, OPENAI_API_KEY
from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.messages.models import NATSMessage
from modules.nats.publish_message import publish_message_to_jetstream

# Langchain

from langchain_community.graphs import Neo4jGraph
from langchain.chains.conversation.memory import ConversationBufferMemory
from langchain.agents import AgentType, initialize_agent
from modules.langchain.tools import create_tools
from langchain_openai import ChatOpenAI
from .cypher_templates import CYPHER_GENERATION_TEMPLATE

# Warning control
import warnings
warnings.filterwarnings("ignore")

recipient_patterns = [
    re.compile(r'^@?(\w+):'),  # Matches "trillian:" or "@trillian:"
    re.compile(r'^@(\w+)'),  # Matches "@trillian"
]

# Define patterns to identify bot message_processing or unwanted content
bot_nicknames = ['twatbot', 'ballsbot', 'thufir']
url_pattern = re.compile(r'https?://[^\s]+')
twitter_expansion_pattern = re.compile(r'\[.*twitter.com.*\]')

# Initialize your Neo4jAdapter with connection details
neo4j_adapter = Neo4jAdapter(uri=NEO4J_URI, username="neo4j",
                             password=NEO4J_PASSWORD)

graph = Neo4jGraph(url=NEO4J_URI, username="neo4j", password=NEO4J_PASSWORD,
                   database="neo4j")

memory = ConversationBufferMemory(memory_key="chat_history", return_messages=True)


def generate_cypher_query(schema, question):
    return CYPHER_GENERATION_TEMPLATE.format(schema=schema, question=question)


class GenericMessage(BaseModel):
    id: Optional[int]  # Some platforms might not have an explicit message ID
    message: str
    nick: str  # The user identifier, might be a username or display name
    channel: Optional[str]  # Not all message_processing are sent in a channel context
    timestamp: datetime
    platform: str  # Could be 'irc', 'discord', 'slack', 'telegram', etc.


async def process_generic_message(message: NATSMessage):
    try:
        # Extract mentioned users or commands based on the message content
        mentioned_users = extract_mentions(message.message)
        commands = extract_commands(message.message)

        # Process the extracted information
        for mentioned_user in mentioned_users:
            # Update relationships or interactions in your database
            print(f"{message.nick} mentioned {mentioned_user} in {message.platform}")

        for command in commands:
            # Process commands as needed
            print(f"Command '{command}' found in message from {message.nick} on {message.platform}")

    except Exception as e:
        print(f"Error processing generic message: {e}")


def extract_mentions(message):
    # This is a simple regex pattern; adjust based on platform syntax
    mention_pattern = re.compile(r'@(\w+)')
    return mention_pattern.findall(message)


def extract_commands(message):
    # Simple example for commands starting with '!'
    command_pattern = re.compile(r'!(\w+)')
    return command_pattern.findall(message)


async def process_command(message: NATSMessage, agent):
    # need to strip out the bots name before passing it to the chain
    bot_name_pattern = re.compile(r'^threadr:\s*',
                                  re.IGNORECASE)
    cleaned_message = re.sub(bot_name_pattern, '',
                             message.message).strip()  # Remove the bot name and strip whitespace
    print("Question:", cleaned_message)
    try:
        # response = cypherChain(cleaned_message)
        response = await agent.arun(input=cleaned_message)
        print(f"process_command - Response: {response}")

        # Check if the response is a string
        if isinstance(response, str):
            response_message = {
                "response": response,
                "channel": message.channel,
                "timestamp": datetime.now().isoformat(),
            }
        else:
            response_message = {
                "response": "I'm not sure how to answer that.",
                "channel": message.channel,
                "timestamp": datetime.now().isoformat(),
            }

        return response_message
    except Exception as e:
        print(f"Failed to process command: {e}")
        return


def is_command(message: str, bot_name: str) -> bool:
    """
    Determines if a given message is a command based on whether it is directed at the bot.

    Parameters:
    - message: The message content as a string.
    - bot_name: The name of the bot.

    Returns:
    - True if the message is directed at the bot, False otherwise.
    """
    # Check if the message starts with the bot's name followed by a colon
    return message.strip().startswith(f"{bot_name}:")


async def process_cloudevent(message_data: NATSMessage,
                             neo4j_adapter: Neo4jAdapter):
    """
    Process the received CloudEvent data.
    """

    # Check if the message is from a known bot or matches the unwanted patterns
    if (message_data.nick in bot_nicknames or
            url_pattern.search(message_data.message) or twitter_expansion_pattern.search(
        message_data.message)):
        print(f"Ignoring bot message or unwanted pattern from {message_data.nick}.")
        return

    # Parse the timestamp using dateutil.parser to handle ISO format with timezone
    timestamp = message_data.timestamp

    mentioned_nick, relationship_type = extract_mentioned_nick(message_data.message)

    if mentioned_nick and relationship_type:
        # If a specific user is mentioned, update the relationship 
        # and add the interaction
        try:
            message_id = await neo4j_adapter.add_interaction(
                message_data.nick,
                mentioned_nick,
                message_data.message,
                timestamp,
                channel=message_data.channel,
                platform=message_data.platform)
            await neo4j_adapter.add_or_update_relationship(message_data.nick,
                                                           mentioned_nick,
                                                           relationship_type)
            print(f"Updated relationship and added interaction between {message_data.nick} and {mentioned_nick}.")
            # You would publish the message details to be processed asynchronously:
            await publish_message_to_jetstream(
                subject=NATS_EMBEDDING_SUBJECT,
                stream=NATS_EMBEDDING_STREAM,
                message_id=message_id,  # You'll need to ensure this is passed correctly
                message_content=message_data.message
            )

            if is_command(message_data.message, BOT_NAME):
                # Initialize the LLM
                llm = ChatOpenAI(temperature=0, openai_api_key=OPENAI_API_KEY)

                # Create tools
                tools = create_tools(neo4j_adapter)

                # Initialize the agent
                agent = initialize_agent(
                    tools,
                    llm,
                    memory=memory,
                    agent=AgentType.CHAT_CONVERSATIONAL_REACT_DESCRIPTION,
                    #agent=AgentType.CHAT_ZERO_SHOT_REACT_DESCRIPTION,
                    verbose=True,
                )

                response = await process_command(message_data, agent)
                if response:
                    print("Publishing response to Jetstream")
                    await publish_message_to_jetstream(
                        subject="outgoing",
                        stream="results",
                        message_id=message_id,
                        message_content=json.dumps(response),
                    )

        except Exception as e:
            print(f"Failed to update Neo4j: {e}")
    else:
        # If no specific user is mentioned, just add the message
        try:
            message_id = await neo4j_adapter.add_message(nick=message_data.nick,
                                                         message=message_data.message,
                                                         timestamp=timestamp,
                                                         channel=message_data.channel,
                                                         platform=message_data.platform)

            # You would publish the message details to be processed asynchronously:
            await publish_message_to_jetstream(
                subject=NATS_EMBEDDING_SUBJECT,
                stream=NATS_EMBEDDING_STREAM,
                message_id=message_id,  # You'll need to ensure this is passed correctly
                message_content=message_data.message
            )

        except Exception as e:
            print(f"Failed to add message to Neo4j: {e}")


def extract_relationship_data(message):
    """
    Extracts to_user from message if it contains mentions.
    Returns to_user and relationship type or None, None if no mention is found.
    """
    for pattern in recipient_patterns:
        match = pattern.search(message)
        if match:
            # Found a mention, assuming "MENTIONED" relationship
            return match.group(1), "MENTIONED"
    return None, None


def extract_mentioned_nick(message):
    """
    Extracts a mentioned user from the message, if present.
    """
    for line in message.splitlines():
        if ": " in line:
            mentioned_nick, _, _ = line.partition(": ")
            return mentioned_nick.strip(), "MENTIONED"
    return None, None
