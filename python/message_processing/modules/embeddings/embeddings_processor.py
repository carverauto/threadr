import json
import torch
from modules.messages.models import VectorEmbeddingMessage
from .embeddings import EmbeddingInterface, get_embedding_model


class EmbeddingsProcessor:
    def __init__(self, neo4j_adapter, embedding_model: EmbeddingInterface):
        self.neo4j_adapter = neo4j_adapter
        self.embedding_model = embedding_model if embedding_model else get_embedding_model()

    async def save_embedding(self, vector, message_id):
        print("Saving embedding for message:", message_id)
        # Ensure vector is in a format that Neo4j can store (e.g., list of floats)
        embedding_vector = vector.tolist() if torch.is_tensor(vector) else vector

        async with self.neo4j_adapter.driver.session() as session:
            # Define the Cypher query for updating the message with the embedding
            cypher = """
            MATCH (msg:Message)
            WHERE id(msg) = $message_id
            SET msg.embedding = $embedding
            RETURN msg
            """
            parameters = {"message_id": message_id, "embedding": embedding_vector}
            # Run the query
            result = await session.run(cypher, parameters)
            record = await result.single()
            if record:
                print(f"Updated message {message_id} with embedding.")
            else:
                print(f"Failed to find message {message_id} to update with embedding.")

    async def process_embedding(self, msg):
        try:
            message_dict = json.loads(msg.data.decode())
            print("Processing message for embedding:", message_dict)
            message_data = VectorEmbeddingMessage(**message_dict)
            embeddings = self.embedding_model.create_embeddings([message_data.content])
            if not embeddings:
                print("No embeddings created for message:", message_data.message_id)
                return
            await self.save_embedding(embeddings[0], message_data.message_id)
            print("Embedding saved for message ID:", message_data.message_id)
        except Exception as e:
            print(f"Error processing message for embedding: {e}")
        finally:
            await msg.ack()
