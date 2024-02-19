from neo4j import GraphDatabase


class Neo4jAdapter:
    def __init__(self, uri, user, password):
        self.driver = GraphDatabase.driver(uri, auth=(user, password))

    def close(self):
        self.driver.close()

    def add_relationship(self, from_user, to_user, relationship_type):
        with self.driver.session() as session:
            session.write_transaction(self._create_and_return_relationship,
                                      from_user, to_user, relationship_type)

    @staticmethod
    def _create_and_return_relationship(
        tx,
        from_user,
        to_user,
        relationship_type
    ):
        query = (
            "MERGE (a:User {name: $from_user}) "
            "MERGE (b:User {name: $to_user}) "
            "MERGE (a)-[r:%s]->(b) "
            "RETURN type(r)" % relationship_type
        )
        result = tx.run(query, from_user=from_user, to_user=to_user)
        return result.single()[0]

    def query_relationships(self, user):
        with self.driver.session() as session:
            result = session.read_transaction(
                self._find_and_return_relationships, user)
        return result

    @staticmethod
    def _find_and_return_relationships(tx, user):
        query = (
            "MATCH (a:User {name: $user})-[r]->(b) "
            "RETURN b.name AS name, type(r) AS relationshipType"
        )
        result = tx.run(query, user=user)
        return [{"name": record["name"], "relationshipType":
                 record["relationshipType"]} for record in result]
