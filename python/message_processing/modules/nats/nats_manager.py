# modules/natsctl/nats_manager.py

from nats.aio.client import Client as NATS


class NATSManager:
    def __init__(self, nats_url, nkeyseed):
        self.nats_url = nats_url
        self.nkeyseed = nkeyseed
        self.nc = NATS()
        self.js = None

    async def connect(self):
        await self.nc.connect(servers=[self.nats_url], nkeys_seed_str=self.nkeyseed)
        self.js = self.nc.jetstream()
        print("Connected to NATS and initialized JetStream.")

    async def disconnect(self):
        await self.nc.close()
        print("Disconnected from NATS.")
