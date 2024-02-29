from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain.chains import RetrievalQA
from langchain.chat_models import ChatOllama
from langchain_community.vectorstores.neo4j_vector import Neo4jVector
from configs.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD
import tracemalloc

tracemalloc.start()

model_name = "sentence-transformers/all-mpnet-base-v2"

# Your Sentence Transformer Configuration
embedding_model = HuggingFaceEmbeddings(
    model_name=model_name,
)

chat_llm = ChatOllama(
    base_url="http://192.168.1.80:11434",
    model="llama2:chat"
)

try:
    threadr_chat_vector = Neo4jVector.from_existing_index(
        embedding_model,
        url=NEO4J_URI,
        username=NEO4J_USERNAME,
        password=NEO4J_PASSWORD,
        index_name="message-embeddings",
        embedding_node_property="embedding",
        text_node_property="content"
    )
except Exception as e:
    print("Error connecting to vectorStore:", e)

chat_retriever = RetrievalQA.from_llm(
    llm=chat_llm,
    retriever=threadr_chat_vector.as_retriever(),
)


result = chat_retriever.invoke(
    {"query": "leku", "top_k": 5}
)

"""
try:
    result = threadr_chat_vector.similarity_search(
        "leku",
        top_k=5
    )
    threadr_chat_vector._driver.close()
except Exception as e:
    print("Error searching for similar documents:", e)

# Display results
for doc in result:
    try:
        print(f"[{doc.metadata['timestamp']}] {doc.page_content}")
        # print(doc.metadata)
    except Exception as e:
        print(f"Error displaying document: {e}")
        print(doc)
"""