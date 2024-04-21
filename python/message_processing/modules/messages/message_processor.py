# modules/messages/message_processor.py
import json
from datetime import datetime
from modules.messages.models import NATSMessage
from modules.cloudevents.cloudevents_handler import process_cloudevent
from modules.nats.nats_producer import NATSProducer
from modules.messages.models import User, Mention


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
                # Ensure to parse the timestamp correctly and handle potential missing fields safely
                timestamp = message_dict.get('timestamp')
                if timestamp:
                    timestamp = datetime.fromisoformat(timestamp)

                # Construct the NATSMessage with proper handling for optional fields
                user_data = message_dict.get('user', {})
                user = User(
                    id=user_data.get('id'),
                    email=user_data.get('email'),
                    username=user_data.get('username'),
                    avatar=user_data.get('avatar'),
                    global_name=user_data.get('global_name'),
                    verified=user_data.get('verified'),
                    mfa_enabled=user_data.get('mfa_enabled'),
                    bot=user_data.get('bot')
                ) if user_data else None

                mentions = [
                    Mention(
                        id=mention.get('id'),
                        email=mention.get('email'),
                        username=mention.get('username'),
                        avatar=mention.get('avatar'),
                        global_name=mention.get('global_name'),
                        verified=mention.get('verified'),
                        mfa_enabled=mention.get('mfa_enabled'),
                        bot=mention.get('bot')
                    ) for mention in message_dict.get('mentions', [])
                ] if 'mentions' in message_dict else None

                nats_message = NATSMessage(
                    id=message_dict.get('id'),
                    message=message_dict.get('message'),
                    user=user,
                    mentions=mentions,
                    channel=message_dict.get('channel'),
                    channel_id=message_dict.get('channel_id'),
                    timestamp=timestamp,
                    platform=message_dict.get('platform'),
                    embedding=message_dict.get('embedding')
                )

                await process_cloudevent(nats_message, self.neo4j_adapter, self.producer)
            else:
                print("Neo4j adapter not initialized.")
        except Exception as e:
            print(f"messageProcessor: Error processing message: {e}")
            # Optionally, handle or log the error more comprehensively here
