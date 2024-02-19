from neo4j import AsyncGraphDatabase


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
