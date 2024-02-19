from neo4j import AsyncSession, GraphDatabase


class Neo4jAdapter:
    def __init__(self, uri, user, password):
        self.driver = GraphDatabase.driver(uri, auth=(user, password), encrypted=False)

    async def close(self):
        await self.driver.close()  # Make sure to close the driver asynchronously

    async def add_relationship(self, from_user, to_user, relationship_type):
        async with self.driver.session() as session:  # Use an async session
            await session.write_transaction(self._create_and_return_relationship,
                                            from_user, to_user, relationship_type)

    @staticmethod
    async def _create_and_return_relationship(tx, from_user, to_user, relationship_type):
        query = (
            "MERGE (a:User {name: $from_user}) "
            "MERGE (b:User {name: $to_user}) "
            "MERGE (a)-[r:{relationship_type}]->(b) "  # Use parameterized query for relationship type
            "RETURN type(r)"
        )
        result = await tx.run(query, from_user=from_user, to_user=to_user, relationship_type=relationship_type)
        return await result.single()[0]

    async def query_relationships(self, user):
        async with self.driver.session() as session:  # Use an async session
            result = await session.read_transaction(
                self._find_and_return_relationships, user)
        return result

    @staticmethod
    async def _find_and_return_relationships(tx, user):
        query = (
            "MATCH (a:User {name: $user})-[r]->(b) "
            "RETURN b.name AS name, type(r) AS relationshipType"
        )
        result = await tx.run(query, user=user)
        return [{"name": record["name"], "relationshipType": record["relationshipType"]} for record in await result.list()]
