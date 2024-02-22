from neo4j import AsyncGraphDatabase
from datetime import datetime
from typing import Optional


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

    async def add_or_update_relationship(self, from_user, to_user, 
                                         relationship_type):
        async with self.driver.session() as session:
            result = await session.write_transaction(
                self._add_or_update_relationship_tx, from_user, to_user,
                relationship_type)
            return result

    @staticmethod
    async def _add_or_update_relationship_tx(tx, from_user, to_user,
                                             relationship_type):
        cypher = """
            MERGE (a:User {name: $from_user})
            MERGE (b:User {name: $to_user})
            MERGE (a)-[r:RELATIONSHIP {type: $relationshipType}]->(b)
            ON CREATE SET r.weight = 1
            ON MATCH SET r.weight = r.weight + 1
            RETURN r.weight as weight
        """
        result = await tx.run(cypher, from_user=from_user, to_user=to_user,
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

    async def add_message(self, nick: str, message: str, timestamp: datetime,
                          channel: Optional[str] = None,
                          platform: str = "generic"):

        # Prepare the parameters for the Cypher query
        params = {
            'nick': nick,
            'message': message,
            'timestamp': timestamp.isoformat(),
            'platform': platform,
        }

        async with self.driver.session() as session:
            cypher = """
            MERGE (user:User {name: $nick})
            CREATE (msg:Message {content: $message, timestamp: $timestamp,
            platform: $platform})
            MERGE (user)-[:SENT]->(msg)
            """
            if channel:
                cypher += """
                MERGE (chan:Channel {name: $channel})
                MERGE (msg)-[:POSTED_IN]->(chan)
                """
                params['channel'] = channel
            # Add RETURN id(msg) to return the Neo4j node ID of the created message
            cypher += " RETURN id(msg) as messageId"

            result = await session.run(cypher, **params)
            record = await result.single()
            if record:
                messageId = record["messageId"]
                print(f"Message from '{nick}' added to the graph with ID {messageId}.")
                return messageId
            else:
                print(f"Failed to add message from '{nick}' to the graph.")
                return None

    async def add_interaction(self, from_user: str, to_user: Optional[str],
                              message_content: str, timestamp: datetime, 
                              channel: Optional[str],
                              platform: str = "generic"):
        async with self.driver.session() as session:
            # Create/merge the user, message, and channel nodes
            # Always link the message to the channel and sender
            cypher = """
            MERGE (from:User {name: $from_user})
            MERGE (chan:Channel {name: $channel})
            CREATE (msg:Message {content: $message_content,
            timestamp: $timestamp, platform: $platform})
            MERGE (from)-[:SENT]->(msg)
            MERGE (msg)-[:POSTED_IN]->(chan)
            """
            
            params = {
                "from_user": from_user,
                "message_content": message_content,
                "timestamp": timestamp.isoformat(),
                "channel": channel,
                "platform": platform
            }
            
            # If the message is directed at another user, add that relationship
            if to_user:
                cypher += """
                MERGE (to:User {name: $to_user})
                MERGE (msg)-[:MENTIONED]->(to)
                MERGE (from)-[r:INTERACTED_WITH]->(to)
                    ON CREATE SET r.weight = 1
                    ON MATCH SET r.weight = r.weight + 1
                """
                params["to_user"] = to_user

            # Add RETURN statement to get the ID of the created message node
            cypher += " RETURN ID(msg) AS messageId"
            
            result = await session.run(cypher, **params)
            record = await result.single()

            print(f"Result: {result} Record: {record}")
            
            if record:
                messageId = record["messageId"]
                print("Message from '{}' added to the graph, directed to '{}',"
                      .format(from_user, to_user), "in channel '{}'."
                      .format(channel))

                return messageId
            else:
                print(f"Failed to add message from '{from_user}' to the graph.")
                return None

               