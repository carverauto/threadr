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
        self.driver = AsyncGraphDatabase.driver(self.uri, auth=(self.username, self.password))

    async def close(self):
        await self.driver.close()

    async def add_or_update_relationship(self, from_user, to_user, relationship_type):
        async with self.driver.session() as session:
            result = await session.write_transaction(self._add_or_update_relationship_tx, from_user, to_user, relationship_type)
            return result

    @staticmethod
    async def _add_or_update_relationship_tx(tx, from_user, to_user, relationship_type):
        cypher = """
            MERGE (a:User {name: $from_user})
            MERGE (b:User {name: $to_user})
            MERGE (a)-[r:RELATIONSHIP {type: $relationshipType}]->(b)
            ON CREATE SET r.weight = 1
            ON MATCH SET r.weight = r.weight + 1
            RETURN r.weight as weight
        """
        result = await tx.run(cypher, from_user=from_user, to_user=to_user, relationshipType=relationship_type)
        record = await result.single()
        return record["weight"] if record else None

    async def query_relationships(self, user):
        async with self.driver.session() as session:
            result = await session.read_transaction(self._query_relationships_tx, user)
            return result

    @staticmethod
    async def _query_relationships_tx(tx, user):
        cypher = """
            MATCH (a:User {name: $user})-[r]->(b)
            RETURN b.name AS toUser, type(r) AS relationshipType
        """
        result = await tx.run(cypher, user=user)
        relationships = [{"toUser": record["toUser"], "relationshipType": record["relationshipType"]} for record in await result.list()]
        return relationships
    
    async def add_message(self, nick: str, message: str, timestamp: datetime, channel: Optional[str] = None, platform: str = "generic"):
        async with self.driver.session() as session:
            cypher = """
            MERGE (user:User {name: $nick})
            CREATE (msg:Message {content: $message, timestamp: $timestamp, platform: $platform})
            MERGE (user)-[:SENT]->(msg)
            """
            if channel:
                cypher += """
                MERGE (chan:Channel {name: $channel})
                MERGE (msg)-[:POSTED_IN]->(chan)
                """
            await session.run(cypher, nick=nick, message=message, timestamp=timestamp, channel=channel, platform=platform)
            print(f"Message from '{nick}' added to the graph.")

    async def add_interaction(self, from_user: str, to_user: Optional[str], message_content: str, timestamp: datetime, channel: Optional[str], platform: str = "generic"):
        async with self.driver.session() as session:
            # Create/merge the user, message, and channel nodes
            # Always link the message to the channel and sender
            cypher = """
            MERGE (from:User {name: $from_user})
            MERGE (chan:Channel {name: $channel})
            CREATE (msg:Message {content: $message_content, timestamp: $timestamp, platform: $platform})
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
            
            await session.run(cypher, **params)
            print(f"Message from '{from_user}' added to the graph, directed to '{to_user}', in channel '{channel}'.")
    