# modules/embeddings/embedding_interface.py

from typing import List

class EmbeddingInterface:
    def create_embeddings(self, texts: List[str]) -> List[List[float]]:
        """
        Abstract method to create embeddings for a list of texts.
        :param texts: A list of texts to embed.
        :return: A list of embeddings, each embedding is a list of floats.
        """
        pass
