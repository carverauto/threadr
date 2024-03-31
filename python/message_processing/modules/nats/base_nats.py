# modules/nats/base_nats.py

import asyncio
from nats.aio.client import Client as NATS
from typing import Optional

from modules.environment.settings import NATS_URL, NKEYSEED


class BaseNATS:
    """
    Base class for connecting to NATS and initializing a JetStream context.
    """
    def __init__(self, nats_url: str = NATS_URL, nkeyseed: Optional[str] = NKEYSEED):
        self.nats_url = nats_url
        self.nkeyseed = nkeyseed
        self.nc = NATS()
        self.js = None

    async def connect(self):
        if not self.nc.is_connected:
            await self.nc.connect(servers=[self.nats_url], nkeys_seed_str=self.nkeyseed)
            self.js = self.nc.jetstream()
            print(f"Connected to NATS at {self.nats_url}...")
            print("JetStream context initialized...")

    async def disconnect(self):
        if self.nc.is_connected:
            await self.nc.close()
            print("NATS connection closed.")
