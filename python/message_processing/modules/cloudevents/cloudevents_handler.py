# cloudevents_handler.py
import re
from datetime import datetime
from typing import Optional
from modules.messages.models import NATSMessage
# from modules.nats.publish_message import publish_message_to_jetstream
from modules.nats.nats_producer import NATSProducer
from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.environment.settings import (
    NATS_EMBEDDING_SUBJECT, NATS_EMBEDDING_STREAM
)

BOT_NAME = "threadr"  # Ensure this matches the actual bot name used in messages
bot_nicknames = []
url_pattern = re.compile(r'https?://[^\s]+')
twitter_expansion_pattern = re.compile(r'\[.*twitter.com.*\]')
# username_pattern = re.compile(r'^(\w+):\s+')
# Update the pattern to match either a username or a user ID
# username_pattern = re.compile(r'(?:(\w+):\s+|<@(\d+)>)')
# username_pattern = re.compile(r'^(?:(\w+):\s+|<@(\d+)>)', re.M)
username_pattern = re.compile(r'(?<!//)(?<!:)(?<!@\w)(?<!http://)(?<!https://)(?<!ftp://)(?:(\w+):\s+|<@(\d+)>)', re.M)


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


def get_channel_id(platform, channel_name, server=None):
    if platform.lower() == "irc" and server:
        return f"irc:{server}:{channel_name}"
    elif platform.lower() == "discord":
        return channel_name  # Assuming channel_name is the Discord channel ID
    return None  # Default case if no proper ID can be formed


async def process_cloudevent(message_data: NATSMessage, neo4j_adapter: Neo4jAdapter, js):
    """
    Process a message from a CloudEvent.
    :param js:
    :param message_data:
    :param neo4j_adapter:
    :return:
    """

    # Decode Unicode escape sequences in the message
    message_data.message = decode_message(message_data.message)

    # print the message
    print(f"Processing message: {message_data}")

    # Construct channel ID based on the platform
    if message_data.platform.lower() == "irc":
        message_data.channel_id = get_channel_id(message_data.platform, message_data.channel,
                                                 message_data.server)
    elif message_data.platform.lower() == "discord":
        # For Discord, assume channel_id is correctly populated
        message_data.channel_id = message_data.channel_id

    # Check if user information is missing and handle accordingly
    if message_data.user is None:
        print("Error: Message data does not contain user information.")
        return  # Consider how you want to handle messages with no user info

    # Initialize a list to hold all mentions processed
    all_mentions = []

    # Check if the platform is IRC or similar that uses text-based mentions
    if message_data.platform.lower() == "irc":
        mentioned_nick, relationship_type = extract_mentioned_nick(message_data.message)
        if mentioned_nick:
            all_mentions.append((mentioned_nick, relationship_type))

    # For platforms like Discord with JSON structured mentions
    elif message_data.platform.lower() == "discord" and message_data.mentions:
        for mention in message_data.mentions:
            # Use a standard relationship type or customize based on logic
            all_mentions.append((mention.username, "MENTIONED"))

    # If a specific user is mentioned, update the relationship and add the interaction
    for mentioned_nick, relationship_type in all_mentions:
        try:
            # Add or update the interaction and relationship in Neo4j
            message_id = await neo4j_adapter.add_interaction(
                message_data.user.username if message_data.user else None,
                mentioned_nick,
                message_data,
                relationship_type
            )
            await neo4j_adapter.add_or_update_relationship(
                message_data.nick,
                mentioned_nick,
                relationship_type
            )
            print(
                f"MSGID: {message_id} - Updated relationship and added interaction between {message_data.nick} and {mentioned_nick}.")
            # Publish the message to Jetstream for embedding
            message_data = {
                "message_id": message_id,
                "content": {
                    "response": message_data.message,
                    "channel": message_data.channel,
                    "timestamp": datetime.now().isoformat()
                }
            }
            await js.publish_message(
                subject=NATS_EMBEDDING_SUBJECT,
                message_data=message_data
            )
            print(f"Published message ID {message_id} to Jetstream subject '{NATS_EMBEDDING_SUBJECT}'.")
            return
        except Exception as e:
            print(f"Failed to update: {e}")

    else:
        if is_command(message_data.message):
            command = extract_command_from_message(message_data.message)
            if command:
                print("Command found: ", command)
                # await send_response_message(response_message, message_id, "outgoing", "results", message_data.channel)
            else:
                print("Command found but not recognized.")
                print("Message: ", message_data.message)
        await handle_generic_message(message_data, neo4j_adapter, js)


async def handle_generic_message(message_data: NATSMessage, neo4j_adapter: Neo4jAdapter, producer: NATSProducer):
    """
    Handle a generic message that is not a command, log to Neo4j,
    and publish to Jetstream for embedding.
    :param producer:
    :param message_data:
    :param neo4j_adapter:
    :return:
    """
    # Example: Log the message to Neo4j and publish to Jetstream for embedding
    message_id = await neo4j_adapter.add_message(message_data)
    print(f"Added message with ID: {message_id}")
    print(f"Publishing message to Jetstream for embedding: {message_data.message}")
    message_data = {
        "message_id": message_id,
        "content": {
            "response": message_data.message,
            "channel": message_data.channel,
            "timestamp": datetime.now().isoformat()
        }
    }
    await producer.publish_message(
        subject=NATS_EMBEDDING_SUBJECT,
        message_data=message_data
    )
    print(f"Published message ID {message_id} to Jetstream subject '{NATS_EMBEDDING_SUBJECT}'.")


def extract_mentioned_nick(message):
    """
    Extracts a mentioned user from the message, if present, while ensuring that the mentions are not part of a URL.

    Parameters:
        message (str): The message string to search for mentions.

    Returns:
        tuple: (mentioned_nick, "MENTIONED") if a mention is found, otherwise (None, None).
    """
    match = username_pattern.search(message)
    if match:
        mentioned_nick = match.group(1) or match.group(2)  # Group 1 for names, Group 2 for IDs
        if mentioned_nick:
            return mentioned_nick.strip(), "MENTIONED"
    return None, None


def decode_message(message):
    """ Decode Unicode escape sequences in a string. """
    return bytes(message, "utf-8").decode("unicode_escape")
