from langchain_core.tools import BaseTool


class VectorSimilaritySearchTool(BaseTool):
    name: str = "VectorSimilaritySearch"
    description: str = "Performs vector similarity search."

    def __init__(self, vector_index):
        self.vector_index = vector_index

    def _run(self, message: str) -> str:
        # Implement the logic to perform vector similarity search using self.vector_index
        result = self.vector_index.similarity_search(query=message, top_k=5)
        return str(result)