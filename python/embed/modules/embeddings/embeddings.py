# src/embeddings.py

from typing import List
from langchain_community.embeddings import HuggingFaceEmbeddings


class EmbeddingInterface:
    def create_embeddings(self, texts: List[str]) -> List[List[float]]:
        """
        Abstract method to create embeddings for a list of texts.
        :param texts: A list of texts to embed.
        :return: A list of embeddings, each embedding is a list of floats.
        """
        pass


class SentenceTransformerEmbedding(EmbeddingInterface):
    def __init__(self, model_name: str = 'sentence-transformers/all-mpnet-base-v2'):
        """
        Initializes the embedding model using HuggingFace's transformers.
        :param model_name: Name of the model to use for generating embeddings.
        """
        self.embedding_model = HuggingFaceEmbeddings(model_name=model_name)

    def create_embeddings(self, texts: List[str]) -> List[List[float]]:
        """
        Creates embeddings for a list of texts using the specified HuggingFace model.
        :param texts: A list of texts to embed.
        :return: A list of embeddings, each embedding is a list of floats.
        """
        # Generate embeddings using the HuggingFaceEmbeddings class
        embeddings = self.embedding_model(texts)
        return embeddings
