# modules/neo4j/neo4j_adapter.py

from neo4j import AsyncGraphDatabase
from modules.messages.models import NATSMessage


class Neo4jAdapter:
    def __init__(self, uri, username, password):
        self.uri = uri
        self.username = username
        self.password = password
        self.driver = None

    async def connect(self):
        self.driver = AsyncGraphDatabase.driver(self.uri, auth=(self.username,
                                                                self.password))

    async def close(self):
        await self.driver.close()

    async def add_or_update_user(self, user):
        async with self.driver.session() as session:
            cypher = """
            MERGE (u:User {id: $id})
            ON CREATE SET u.username = $username, u.email = $email, u.avatar = $avatar,
                          u.global_name = $global_name, u.verified = $verified, u.mfa_enabled = $mfa_enabled,
                          u.bot = $bot
            ON MATCH SET u.username = $username, u.email = $email, u.avatar = $avatar,
                         u.global_name = $global_name, u.verified = $verified, u.mfa_enabled = $mfa_enabled,
                         u.bot = $bot
            RETURN u
            """
            result = await session.run(cypher, id=user.id, username=user.username, email=user.email,
                                       avatar=user.avatar, global_name=user.global_name, verified=user.verified,
                                       mfa_enabled=user.mfa_enabled, bot=user.bot)
            record = await result.single()
            return record['u'] if record else None

    async def add_or_update_relationship(self, from_user_id, to_user_id,
                                         relationship_type):
        async with self.driver.session() as session:
            result = await session.write_transaction(
                self._add_or_update_relationship_tx, from_user_id, to_user_id,
                relationship_type)
            return result

    @staticmethod
    async def _add_or_update_relationship_tx(tx, from_user_id, to_user_id,
                                             relationship_type):
        cypher = """
            MERGE (a:User {id: $from_user_id})
            MERGE (b:User {id: $to_user_id})
            MERGE (a)-[r:CONNECTION {type: $relationshipType}]->(b)
            ON CREATE SET r.weight = 1
            ON MATCH SET r.weight = r.weight + 1
            RETURN r.weight as weight
        """
        result = await tx.run(cypher, from_user=from_user_id, to_user=to_user_id,
                              relationshipType=relationship_type)
        record = await result.single()
        return record["weight"] if record else None

    async def query_relationships(self, user):
        async with self.driver.session() as session:
            # Assuming you created an index on User.name
            cypher = """
            MATCH (a:User {name: $user})-[r]->(b)
            RETURN b.name AS toUser, type(r) AS relationshipType
            """
            result = await session.run(cypher, user=user)
            return [{"toUser": record["toUser"], "relationshipType":
                record["relationshipType"]} for record in result]

    async def add_message(self, message_data: NATSMessage):

        # Prepare the parameters for the Cypher query
        params = {
            'username': message_data.user.username,
            'message': message_data.message,
            'timestamp': message_data.timestamp.isoformat(),
            'platform': message_data.platform,
        }
        cypher = """
                    MERGE (user:User {username: $username})
                    CREATE (msg:Message {content: $message, timestamp: $timestamp,
                    platform: $platform})
                    MERGE (user)-[:SENT]->(msg)
        """
        async with self.driver.session() as session:

            if message_data.channel:
                cypher += """
                MERGE (chan:Channel {name: $channel, id: $channel_id})
                MERGE (msg)-[:POSTED_IN]->(chan)
                """
                params.update({
                    'channel': message_data.channel,
                    'channel_id': message_data.channel_id
                })
            # Add RETURN id(msg) to return the Neo4j node ID of the created message
            cypher += " RETURN id(msg) as messageId"

            result = await session.run(cypher, **params)
            record = await result.single()
            if record:
                messageId = record["messageId"]
                print(f"Message from '{message_data.user.username}' added to the graph with ID {messageId}.")
                return messageId
            else:
                print(f"Failed to add message from '{message_data.user.username}' to the graph.")
                return None

    async def add_interaction(self, message_data: NATSMessage, relationship_type: str):
        if message_data.user is None:
            print("No user data available to process interaction.")
            return None  # Skip processing this message or handle as needed

        async with self.driver.session() as session:
            # Build the initial part of the cypher query to merge the sender user node
            cypher = """
            MERGE (sender:User {id: $user_id})
            ON CREATE SET sender.username = $username, sender.email = $email, sender.avatar = $avatar, sender.global_name = $global_name, sender.verified = $verified, sender.mfa_enabled = $mfa_enabled, sender.bot = $bot
            ON MATCH SET sender.username = $username, sender.email = $email, sender.avatar = $avatar, sender.global_name = $global_name, sender.verified = $verified, sender.mfa_enabled = $mfa_enabled, sender.bot = $bot
            """

            # Prepare user parameters
            user_params = {
                "user_id": message_data.user.id,
                "username": message_data.user.username,
                "email": message_data.user.email,
                "avatar": message_data.user.avatar,
                "global_name": message_data.user.global_name,
                "verified": message_data.user.verified,
                "mfa_enabled": message_data.user.mfa_enabled,
                "bot": message_data.user.bot,
            }

            # Append the creation of the message node and its relationships
            cypher += """
            CREATE (msg:Message {content: $content, timestamp: $timestamp, platform: $platform})
            MERGE (sender)-[:SENT]->(msg)
            MERGE (chan:Channel {id: $channel_id})
            ON CREATE SET chan.name = $channel
            MERGE (msg)-[:POSTED_IN]->(chan)
            """

            # Extend parameters with message details
            params = {
                **user_params,
                "content": message_data.message,
                "timestamp": message_data.timestamp.isoformat() if message_data.timestamp else None,
                "platform": message_data.platform,
                "channel_id": message_data.channel_id,
                "channel": message_data.channel,
            }

            # Handle mentions and establish MENTIONED relationships
            if message_data.mentions:
                for index, mention in enumerate(message_data.mentions):
                    cypher += f"""
                    MERGE (mentioned{index}:User {{id: $mention_id{index}}})
                    ON CREATE SET mentioned{index}.username = $mention_username{index}
                    MERGE (msg)-[:MENTIONED]->(mentioned{index})
                    """
                    params[f"mention_id{index}"] = mention.id
                    params[f"mention_username{index}"] = mention.username

            # Finalize the Cypher query to return the created message ID
            cypher += "RETURN id(msg) AS messageId"

            # Run the session with the composed Cypher and parameters
            result = await session.run(cypher, **params)
            record = await result.single()

            if record:
                print(f"Interaction added with message ID {record['messageId']}.")
                return record['messageId']
            else:
                print("Failed to add interaction to the graph.")
                return None
