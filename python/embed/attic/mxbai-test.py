from sentence_transformers import SentenceTransformer
from sentence_transformers.util import cos_sim

# 1. load model
model = SentenceTransformer("mixedbread-ai/mxbai-embed-large-v1")

# For retrieval you need to pass this prompt.
query = 'Represent this sentence for searching relevant passages: A man is eating a piece of bread'

docs = [
    query,
    "A man is eating food.",
    "A man is eating pasta.",
    "The girl is carrying a baby.",
    "A man is riding a horse.",
]

# 2. Encode
embeddings = model.encode(docs)

similarities = cos_sim(embeddings[0], embeddings[1:])
print('similarities:', similarities)
