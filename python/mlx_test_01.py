from mlx_embedding_models.embedding import EmbeddingModel
model = EmbeddingModel.from_registry("bge-small")
texts = [
    "isn't it nice to be inside such a fancy computer, the horse raced past the barn fell"
]
embs = model.encode(texts)
print(embs.shape)
# 2, 384
