import os

NATS_URL = os.getenv("NATSURL", "nats://localhost:4222")
NKEYSEED = os.getenv("NKEYSEED")
USE_QUEUE_GROUP = os.getenv("USE_QUEUE_GROUP", "True").lower() in ["true", "yes", "1"]
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USERNAME = os.getenv("NEO4J_USERNAME", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "")
