from .neo4j_adapter import Neo4jAdapter
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import os
import re
import json
from .models import NATSMessage

recipient_patterns = [
    re.compile(r'^@?(\w+):'),  # Matches "trillian:" or "@trillian:"
    re.compile(r'^@(\w+)'),    # Matches "@trillian"
]

# Define patterns to identify bot messages or unwanted content
bot_nicknames = ['twatbot', 'ballsbot']
url_pattern = re.compile(r'https?://[^\s]+')
twitter_expansion_pattern = re.compile(r'\[.*twitter.com.*\]')

# Initialize your Neo4jAdapter with connection details
neo4j_adapter = Neo4jAdapter(uri="bolt://localhost:7687", username="neo4j",
                             password=os.environ.get("NEO4J_PASSWORD"))


class GenericMessage(BaseModel):
    id: Optional[int]  # Some platforms might not have an explicit message ID
    message: str
    nick: str  # The user identifier, might be a username or display name
    channel: Optional[str]  # Not all messages are sent in a channel context
    timestamp: datetime
    platform: str  # Could be 'irc', 'discord', 'slack', 'telegram', etc.


async def process_generic_message(message: NATSMessage, neo4j_adapter: Neo4jAdapter):
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


async def process_cloudevent(message_data: NATSMessage, neo4j_adapter: Neo4jAdapter):
    """
    Process the received CloudEvent data.
    """
    # Assuming message_data is correctly an instance of NATSMessage and has the necessary attributes.
    print(f"Received a message on '{message_data.channel}': {message_data.message}")

    # Directly using message_data.nick and message_data.message for clarity and avoiding the 'nick not defined' error
    if message_data.nick in bot_nicknames or url_pattern.search(message_data.message) or twitter_expansion_pattern.search(message_data.message):
        print(f"Ignoring bot message or unwanted pattern from {message_data.nick}.")
        return

    mentioned_nick, relationship_type = extract_mentioned_nick(message_data.message)

    # Ensure 'mentioned_nick' and 'relationship_type' are defined before proceeding
    if mentioned_nick and relationship_type:
        try:
            # Call the Neo4j adapter's method with correct parameters
            await neo4j_adapter.add_or_update_relationship(message_data.nick, mentioned_nick, relationship_type)
            print(f"Updated relationship between {message_data.nick} and {mentioned_nick} as {relationship_type}.")
        except Exception as e:
            print(f"Failed to update Neo4j: {e}")


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
