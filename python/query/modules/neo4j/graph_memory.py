# ./query/modules/neo4j/graph_memory.py

from abc import ABC
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field

from langchain.schema import BaseMemory
from langchain.docstore import InMemoryDocstore
#from langchain.embeddings import OpenAIEmbeddings
from modules.embeddings.embeddings import SentenceTransformerEmbedding
from langchain_community.vectorstores import Neo4jVector


class GraphMemory(BaseMemory, BaseModel, ABC):
    """Memory class for storing conversation memory in a Neo4j graph."""

    neo4j_url: str = ""
    neo4j_username: str = ""
    neo4j_password: str = ""
    index_name: str = "default"
    embedding_function: Any = None
    return_messages: bool = False
    top_k: int = 5
    docstore: InMemoryDocstore = Field(default_factory=InMemoryDocstore)

    def __init__(self, **kwargs: Any):
        super().__init__(**kwargs)
        self.docstore = InMemoryDocstore()
        #self.embedding_function = OpenAIEmbeddings()
        self.embedding_function = SentenceTransformerEmbedding()
        self.vectorstore = Neo4jVector.from_existing_index(
            self.embedding_function,
            url=self.neo4j_url,
            username=self.neo4j_username,
            password=self.neo4j_password,
            index_name=self.index_name,
        )

    def add_message(self, message: Dict[str, str]) -> List[str]:
        """Add a message to the memory."""
        if message is None:
            raise ValueError("Message cannot be None")

        message_texts = self.docstore.add_documents([message["content"]])
        self.vectorstore.add_documents([{"page_content": message["content"], "metadata": {"role": message["role"]}}])

        if self.return_messages:
            return message_texts
        else:
            return []

    def clear(self) -> None:
        """Clear the docstore and vectorstore."""
        self.docstore = InMemoryDocstore()
        self.vectorstore.delete_index()

    def load_memory_variables(self, values: Dict[str, Any]) -> Dict[str, Any]:
        """Return history and context to be used in the prompt."""
        docs = self.vectorstore.similarity_search_with_score(values["input"], k=self.top_k)
        context = [f"{doc[0].metadata['role']}: {doc[0].page_content}" for doc in docs]
        values["history"] = "\n".join(context)
        return values

    def save_context(self, inputs: Dict[str, Any], outputs: Dict[str, str]) -> None:
        """Save the context of an interaction."""
        self.add_message({"role": "Human", "content": inputs["input"]})
        self.add_message({"role": "Assistant", "content": outputs["output"]})