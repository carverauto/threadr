# cloudevents_handler.py

from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import re
from modules.environment.settings import NATS_EMBEDDING_SUBJECT, NATS_EMBEDDING_STREAM, \
    NEO4J_PASSWORD, NEO4J_URI, BOT_NAME
from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.messages.models import NATSMessage
from modules.nats.publish_message import publish_message_to_jetstream
import os
import textwrap

# Langchain

from langchain_community.graphs import Neo4jGraph
from langchain_community.vectorstores import Neo4jVector
from langchain_openai import OpenAIEmbeddings
# from langchain.chains import RetrievalQAWithSourcesChain
from langchain.prompts.prompt import PromptTemplate
from langchain.chains import GraphCypherQAChain
from langchain_openai import ChatOpenAI
from .cypher_templates import CYPHER_GENERATION_TEMPLATE

# Warning control
import warnings

from modules.environment.settings import OPENAI_API_KEY

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


async def process_command(message: NATSMessage, message_id: str):
    # refresh the graph
    graph.refresh_schema()
    print(textwrap.fill(graph.schema, 60))

    vector_index = Neo4jVector.from_existing_graph(
        OpenAIEmbeddings(
            model="text-embedding-3-small",
            dimensions=1536,
        ),
        url=NEO4J_URI,
        username="neo4j",
        password=NEO4J_PASSWORD,
        index_name="message-embeddings",
        node_label="Message",
        text_node_properties=['content', 'platform', 'timestamp'],
        embedding_node_property="embedding",
    )

    # response = vector_index.similarity_search(
    #    query=message.message,
    # )
    # print(response)

    CYPHER_GENERATION_PROMPT = PromptTemplate(
        input_variables=["schema", "question"],
        template=CYPHER_GENERATION_TEMPLATE,
    )
    cypherChain = GraphCypherQAChain.from_llm(
        ChatOpenAI(temperature=0, openai_api_key=OPENAI_API_KEY),
        graph=graph,
        verbose=True,
        cypher_prompt=CYPHER_GENERATION_PROMPT,
    )

    response = cypherChain.run(message.message)
    print(textwrap.fill(response, 60))
    response_subject = "outgoing"
    response_stream = "results"

    response_message = {
        "response": response,
        "channel": message.channel,
        "timestamp": datetime.now().isoformat(),
    }

    return response_message


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
                response = await process_command(message_data, message_id)
                await publish_message_to_jetstream(
                    subject="outgoing",
                    stream="results",
                    message_id=message_id,
                    message_content=response,
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
