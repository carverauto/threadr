# cloudevents_handler.py
import re
from datetime import datetime
from typing import Optional
from modules.messages.models import NATSMessage
from modules.nats.publish_message import publish_message_to_jetstream
from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.environment.settings import (
    NATS_EMBEDDING_SUBJECT, NATS_EMBEDDING_STREAM, BOT_NAME
)
from modules.langchain.utils import format_graph_output_as_response, send_response_message, execute_graph_with_command

bot_nicknames = ['twatbot', 'ballsbot', 'thufir']
url_pattern = re.compile(r'https?://[^\s]+')
twitter_expansion_pattern = re.compile(r'\[.*twitter.com.*\]')


def is_command(message: str) -> bool:
    # Adjust to check for bot name followed by a recognizable command pattern
    command_pattern = re.compile(rf'^{BOT_NAME}:\s*!(\w+)')
    return bool(command_pattern.search(message))


def extract_command_from_message(message: str) -> Optional[str]:
    # Adjusted to extract command after bot name and colon
    command_pattern = re.compile(rf'^{BOT_NAME}:\s*!(\w+)')
    match = command_pattern.search(message)
    return match.group(1) if match else None


async def process_cloudevent(message_data: NATSMessage, neo4j_adapter: Neo4jAdapter, graph):
    if (message_data.nick in bot_nicknames or
            url_pattern.search(message_data.message) or
            twitter_expansion_pattern.search(message_data.message)):
        print(f"Ignoring bot message or unwanted pattern from {message_data.nick}.")
        return

    if is_command(message_data.message):
        command = extract_command_from_message(message_data.message)
        if command:
            graph_output = await execute_graph_with_command(graph, command, message_data)
            response_message = format_graph_output_as_response(graph_output, message_data.channel)
            await send_response_message(response_message)
        else:
            print("Command found but not recognized.")
            print("Message: ", message_data.message)
    else:
        # Handle non-command messages, e.g., logging, Neo4j updates
        await handle_generic_message(message_data, neo4j_adapter)


async def handle_generic_message(message_data: NATSMessage, neo4j_adapter: Neo4jAdapter):
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
        message_content=message_data.message
    )


