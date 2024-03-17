# modules/embeddings/openai_embeddings.py

import os
from typing import List
from openai import OpenAI
from .embedding_interface import EmbeddingInterface


class OpenAIEmbedding(EmbeddingInterface):
    # def __init__(self, model: str = 'text-embedding-3-small', dimensions: int = 1536):
    def __init__(self):
        """
        Initializes the OpenAI model for generating embeddings.
        :param model: The model ID to use for generating embeddings.
        """
        client = OpenAI(api_key=os.getenv("OPEN_AI_KEY"))
        self.client = client

    def create_embeddings(self, texts: List[str]) -> List[List[float]]:
        embeddings = []
        for text in texts:
            try:
                response = self.client.embeddings.create(
                    model="text-embedding-3-small",
                    input=text
                )
                # Assuming each response item is an instance of openai.types.embedding.Embedding
                # and the actual vector is accessible via an attribute (e.g., .embedding)
                # You might need to adjust this based on the actual structure
                if hasattr(response, 'data') and isinstance(response.data, list):
                    for item in response.data:
                        if hasattr(item, 'embedding'):
                            embeddings.append(item.embedding)
                        else:
                            print(f"No embedding found for text: {text}")
                            embeddings.append([])
                else:
                    print(f"Unexpected response structure for text: {text}")
                    embeddings.append([])
            except Exception as e:
                print(f"Failed to generate embedding for text: {text}. Error: {e}")
                embeddings.append([])  # Append an empty list or handle the error as needed
        return embeddings
