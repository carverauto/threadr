from .models import VectorEmbeddingMessage
import json
import torch
from transformers import AutoTokenizer, AutoModel, BitsAndBytesConfig


def create_embeddings(texts):
    max_length = 2048
    # Tokenize texts
    batch_dict = tokenizer(texts, return_tensors="pt", padding=True, truncation=True, max_length=max_length)
    # Compute model outputs
    with torch.no_grad():  # Disable gradient calculation for faster computation
        outputs = model(**batch_dict)
    # Extract embeddings (for simplicity, use the last hidden state directly)
    embeddings = outputs.last_hidden_state.mean(dim=1)
    return embeddings


# Use BitsAndBytesConfig to enable 4-bit quantization
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_use_double_quant=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.bfloat16
)

# Load model and tokenizer
tokenizer = AutoTokenizer.from_pretrained('Salesforce/SFR-Embedding-Mistral')
model = AutoModel.from_pretrained('Salesforce/SFR-Embedding-Mistral',
                                  trust_remote_code=True,
                                  device_map='auto',
                                  torch_dtype=torch.bfloat16,
                                  quantization_config=bnb_config)


class EmbeddingsProcessor:
    def __init__(self, neo4j_adapter):
        self.neo4j_adapter = neo4j_adapter

    async def save_embedding(self, vector, message_id):
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
            # Parse the raw message data into a VectorEmbeddingMessage object
            message_dict = json.loads(msg.data.decode())
            message_data = VectorEmbeddingMessage(**message_dict)

            if self.neo4j_adapter is None:
                print("Neo4j adapter not initialized.")
                return

            print("Message data:", message_data)
            # Assuming 'message_data.message' contains the text to be embedded
            embeddings = create_embeddings([message_data.content])
            # Assuming 'embeddings' is a tensor with shape [1, embedding_size]
            await self.save_embedding(embeddings[0], message_data.message_id)
            print("Embedding saved for message:", message_data.message_id)

        except Exception as e:
            print(f"Error processing message: {e}")
        finally:
            # Correctly acknowledge the message in JetStream context
            await msg.ack()
