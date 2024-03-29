# cloudevents_handler.py
import re
from datetime import datetime
from typing import Optional
from modules.messages.models import NATSMessage
from modules.nats.publish_message import publish_message_to_jetstream
from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.environment.settings import (
    NATS_EMBEDDING_SUBJECT, NATS_EMBEDDING_STREAM
)
from modules.langchain.utils import format_graph_output_as_response, send_response_message, execute_graph_with_command

BOT_NAME = "threadr"  # Ensure this matches the actual bot name used in messages
bot_nicknames = ['twatbot', 'ballsbot', 'thufir']
url_pattern = re.compile(r'https?://[^\s]+')
twitter_expansion_pattern = re.compile(r'\[.*twitter.com.*\]')


def is_command(message: str) -> bool:
    """
    Check if the message contains a command.
    :param message:
    :return:
    """
    # Adjust the pattern to match the expected message format
    command_pattern = re.compile(rf'^{re.escape(BOT_NAME)}:\s*(\w+)')
    match = command_pattern.search(message)
    if match:
        return True
    else:
        return False


def extract_command_from_message(message: str) -> Optional[str]:
    """
    Extract the command from the message.
    :param message:
    :return:
    """
    command_pattern = re.compile(rf'^{re.escape(BOT_NAME)}:\s*(.*)')
    match = command_pattern.search(message)
    if match:
        command = match.group(1).strip()  # .strip() to remove any leading/trailing whitespace
        return command
    else:
        return None


async def process_cloudevent(message_data: NATSMessage, neo4j_adapter: Neo4jAdapter, graph):
    """
    Process a message from a CloudEvent.
    :param message_data:
    :param neo4j_adapter:
    :param graph:
    :return:
    """
    print("Message received: ", message_data)

    if (message_data.nick in bot_nicknames or
            url_pattern.search(message_data.message) or
            twitter_expansion_pattern.search(message_data.message)):
        print(f"Ignoring bot message or unwanted pattern from {message_data.nick}.")
        return

    # Attempt to extract a mentioned user and relationship type from the message
    mentioned_nick, relationship_type = extract_mentioned_nick(message_data.message)
    # If a specific user is mentioned, update the relationship and add the interaction
    if mentioned_nick and relationship_type:
        try:
            # Add or update the interaction and relationship in Neo4j
            message_id = await neo4j_adapter.add_interaction(
                message_data.nick,
                mentioned_nick,
                message_data.message,
                message_data.timestamp,
                channel=message_data.channel,
                platform=message_data.platform
            )
            await neo4j_adapter.add_or_update_relationship(
                message_data.nick,
                mentioned_nick,
                relationship_type
            )
            print(f"Updated relationship and added interaction between {message_data.nick} and {mentioned_nick}.")

            if is_command(message_data.message):
                command = extract_command_from_message(message_data.message)
                if command:
                    final_message_content = await execute_graph_with_command(graph, command, message_data)
                    print("Final message content: ", final_message_content)
                    if final_message_content:
                        response_message = format_graph_output_as_response(final_message_content, message_data.channel)
                        print("Response message: ", response_message)
                        await send_response_message(response_message, message_id, "outgoing", "results", message_data.channel)
                else:
                    print("Command found but not recognized.")
                    print("Message: ", message_data.message)
            else:
                # Handle non-command messages, e.g., logging, Neo4j updates
                await handle_generic_message(message_data, neo4j_adapter)
        except Exception as e:
            print(f"Failed to update Neo4j: {e}")


async def handle_generic_message(message_data: NATSMessage, neo4j_adapter: Neo4jAdapter):
    """
    Handle a generic message that is not a command, log to Neo4j,
    and publish to Jetstream for embedding.
    :param message_data:
    :param neo4j_adapter:
    :return:
    """
    # Example: Log the message to Neo4j and publish to Jetstream for embedding
    message_id = await neo4j_adapter.add_message(
        nick=message_data.nick,
        message=message_data.message,
        timestamp=datetime.now(),  # Adjust as necessary
        channel=message_data.channel,
        platform="platform"  # Adjust as necessary
    )
    await publish_message_to_jetstream(
        subject=NATS_EMBEDDING_SUBJECT,
        stream=NATS_EMBEDDING_STREAM,
        message_id=message_id,
        message_content=message_data.message,
        channel=message_data.channel
    )


def extract_mentioned_nick(message):
    """
    Extracts a mentioned user from the message, if present.
    """
    for line in message.splitlines():
        if ": " in line:
            mentioned_nick, _, _ = line.partition(": ")
            return mentioned_nick.strip(), "MENTIONED"
    return None, None

