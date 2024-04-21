import re
from datetime import datetime
from typing import Optional
from modules.messages.models import NATSMessage
from modules.nats.nats_producer import NATSProducer
from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.environment.settings import NATS_EMBEDDING_SUBJECT, NATS_EMBEDDING_STREAM

import sys

print(sys.path)

BOT_NAME = "threadr"  # Ensure this matches the actual bot name used in messages
url_pattern = re.compile(r'https?://[^\s]+')
twitter_expansion_pattern = re.compile(r'\[.*twitter.com.*\]')
username_pattern = re.compile(r'(?<!//)(?<!:)(?<!@\w)(?<!http://)(?<!https://)(?<!ftp://)(?:(\w+):\s+|<@(\d+)>)', re.M)


def is_command(message: str) -> bool:
    """Check if the message contains a command."""
    command_pattern = re.compile(rf'^{re.escape(BOT_NAME)}:\s*(\w+)')
    return bool(command_pattern.search(message))


def extract_command_from_message(message: str) -> Optional[str]:
    """Extract the command from the message."""
    command_pattern = re.compile(rf'^{re.escape(BOT_NAME)}:\s*(.*)')
    match = command_pattern.search(message)
    return match.group(1).strip() if match else None


async def process_cloudevent(message_data: NATSMessage, neo4j_adapter: Neo4jAdapter, js):
    """Processes a message from a CloudEvent."""
    message_data.message = decode_message(message_data.message)
    print(f"Processing message: {message_data}")

    if message_data.user is None:
        print("Error: Message data does not contain user information.")
        return

    message_data.channel_id = get_channel_id(message_data.platform, message_data.channel, message_data.server)

    mentioned_ids = extract_mentioned_ids(message_data)
    for mentioned_id in mentioned_ids:
        message_id = await neo4j_adapter.add_interaction(message_data, "MENTIONED")
        await neo4j_adapter.add_or_update_relationship(message_data.user.id, mentioned_id, "MENTIONED")
        print(f"Updated relationship and added interaction for message ID {message_id}.")
        embedded_message = create_embedded_message(message_id, message_data)
        await js.publish_message(NATS_EMBEDDING_SUBJECT, embedded_message)

    if is_command(message_data.message):
        command = extract_command_from_message(message_data.message)
        if command:
            print("Command found and processed: ", command)
        else:
            print("Command found but not recognized.")

    if not mentioned_ids and not is_command(message_data.message):
        await handle_generic_message(message_data, neo4j_adapter, js)


def get_channel_id(platform, channel_name, server=None):
    """Constructs a channel identifier based on the platform and server details."""
    if platform.lower() == "irc" and server:
        return f"irc:{server}:{channel_name}"
    elif platform.lower() == "discord":
        return channel_name
    return None


async def handle_generic_message(message_data: NATSMessage, neo4j_adapter: Neo4jAdapter, producer: NATSProducer):
    """Handle a generic message."""
    message_id = await neo4j_adapter.add_message(message_data)
    print(f"Added message with ID: {message_id}")
    message_data = create_embedded_message(message_id, message_data)
    await producer.publish_message(NATS_EMBEDDING_SUBJECT, message_data)


def extract_mentioned_ids(message_data: NATSMessage):
    """Retrieves mentioned ids from mentions in the object."""
    return [mention.id for mention in message_data.mentions] if message_data.mentions else []


def create_embedded_message(message_id, message_data: NATSMessage):
    """Create message content for Jetstream."""
    return {
        "message_id": message_id,
        "content": {
            "response": message_data.message,
            "channel": message_data.channel,
            "timestamp": datetime.now().isoformat()
        }
    }


def decode_message(message):
    """Decode Unicode escape sequences in a string."""
    return bytes(message, "utf-8").decode("unicode_escape")
