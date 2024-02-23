# src/embeddings.py

from abc import ABC, abstractmethod
from typing import List
import torch
from transformers import AutoTokenizer, AutoModel


class EmbeddingInterface(ABC):
    @abstractmethod
    def create_embeddings(self, texts: List[str]) -> List[List[float]]:
        """
        Creates embeddings for a list of texts.

        :param texts: A list of texts to embed.
        :return: A list of embeddings, each embedding is a list of floats.
        """
        pass


class SentenceTransformerEmbedding(EmbeddingInterface):
    def __init__(self, model_name: str = 'sentence-transformers/all-mpnet-base-v2',
                 model_args: dict = None,
                 quantization_config: dict = None
                 ):
        # import BitsAndBytesConfig from transformers if quantization is enabled
        if quantization_config is not None:
            from transformers import BitsAndBytesConfig
            # Load model and tokenizer only once for efficiency
            bnb_config = BitsAndBytesConfig(
                load_in_4bit=True,
                bnb_4bit_use_double_quant=True,
                bnb_4bit_quant_type="nf4",
                bnb_4bit_compute_dtype=torch.bfloat16
            )

        # 4bit quantization (disable if not needed)
        if model_args.pop('enable_mem_efficient_sdp', True):
            torch.backends.cuda.enable_mem_efficient_sdp(True)
        if model_args.pop('enable_flash_sdp', True):
            torch.backends.cuda.enable_flash_sdp(True)

        self.tokenizer = AutoTokenizer.from_pretrained(model_name)
        self.model = AutoModel.from_pretrained(model_name, **model_args,
                                               quantization_config=quantization_config)

    def create_embeddings(self, texts: List[str]) -> List[List[float]]:
        max_length = 2048

        # Tokenize texts (re-using most of your logic)
        batch_dict = self.tokenizer(texts, return_tensors="pt", padding=True, truncation=True, max_length=max_length)

        # Compute model outputs
        with torch.no_grad():
            outputs = self.model(**batch_dict)

        # Extract embeddings
        embeddings = outputs.last_hidden_state.mean(dim=1).tolist()  # Convert to standard lists
        return embeddings

