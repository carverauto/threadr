import os

NATS_URL = os.getenv("NATSURL", "nats://localhost:4222")
NKEYSEED = os.getenv("NKEYSEED")
USE_QUEUE_GROUP = os.getenv("USE_QUEUE_GROUP", "True").lower() in ["true", "yes", "1"]
