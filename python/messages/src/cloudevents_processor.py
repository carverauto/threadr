from .neo4j_adapter import Neo4jAdapter
import os
import re

recipient_patterns = [
    re.compile(r'^@?(\w+):'),  # Matches "trillian:" or "@trillian:"
    re.compile(r'^@(\w+)'),    # Matches "@trillian"
]

# Initialize your Neo4jAdapter with connection details
neo4j_adapter = Neo4jAdapter(uri="bolt://localhost:7687", username="neo4j",
                             password=os.environ.get("NEO4J_PASSWORD"))


async def process_cloudevent(data, neo4j_adapter):
    """
    Process the received CloudEvent data.
    """

    # Extract information from the data to form a relationship
    # For demonstration, let's assume data is a simple dictionary
    # and contains 'from_user', 'to_user', and 'relationship_type'
    nick = data.get('nick')
    message = data.get('message')

    # to_user, relationship_type = extract_relationship_data(message)
    # Attempt to extract a mentioned user from the message
    mentioned_nick, relationship_type = extract_mentioned_nick(message)

    # if from_user and to_user and relationship_type:
    if nick and mentioned_nick and relationship_type:
        # Use the Neo4j adapter to add or update the relationship
        try:
            await neo4j_adapter.add_or_update_relationship(nick, mentioned_nick, relationship_type)
            print(f"Updated relationship between {nick} and {mentioned_nick} "
                  f"as {relationship_type}.")
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
