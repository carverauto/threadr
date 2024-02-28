from langchain_community.graphs import Neo4jGraph
import os

graph = Neo4jGraph(
    url="bolt://localhost:7687",
    username="neo4j",
    password=os.environ.get("NEO4J_PASSWORD")
)

result = graph.query("""
MATCH (user:User)-[:SENT]->(msg:Message)
RETURN user.name AS userName, max(msg.timestamp) AS lastMessageTimestamp
ORDER BY lastMessageTimestamp DESC
""")

print(result)
