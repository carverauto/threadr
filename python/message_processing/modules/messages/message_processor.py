# modules/messages/message_processor.py
import json
from modules.messages.models import NATSMessage
from modules.cloudevents.cloudevents_handler import process_cloudevent
from modules.nats.nats_producer import NATSProducer


class MessageProcessor:
    def __init__(self, neo4j_adapter, producer: NATSProducer):
        self.neo4j_adapter = neo4j_adapter
        self.producer = producer

    async def process_message(self, msg):
        try:
            # Parse the raw message data into a NATSMessage object
            # message_data = NATSMessage.parse_raw(msg.data.decode())
            message_data = NATSMessage.model_validate_json(msg.data.decode())
            if self.neo4j_adapter is not None:
                await process_cloudevent(message_data, self.neo4j_adapter, self.producer)
            else:
                print("Neo4j adapter not initialized.")
        except Exception as e:
            print(f"messageProcessor: Error processing message: {e}")
            # Optionally, handle or log the error appropriately
        finally:
            # Correctly acknowledge the message in JetStream context
            await msg.ack()

    async def process_message_direct(self, message):
        try:
            if self.neo4j_adapter is not None:
                message_dict = json.loads(message)
                nats_message = NATSMessage(message=message_dict.get('message'),nick=message_dict.get('nick'),channel=message_dict.get('channel'),timestamp=message_dict.get('timestamp'),platform=message_dict.get('platform'))
                await process_cloudevent(nats_message, self.neo4j_adapter, self.producer)
            else:
                print("Neo4j adapter not initialized.")
        except Exception as e:
            print(f"messageProcessor: Error processing message: {e}")
            # Optionally, handle or log the error appropriately
