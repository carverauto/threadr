from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_community.vectorstores.neo4j_vector import Neo4jVector
from configs.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD

model_name = "sentence-transformers/all-mpnet-base-v2"
model_kwargs = {"cuda": True}

# Your Sentence Transformer Configuration
embedding_model = HuggingFaceEmbeddings(model_name=model_name, model_kwargs=model_kwargs)

try:
    threadr_chat_vector = Neo4jVector.from_existing_index(
        embedding_model, 
        url=NEO4J_URI,
        username=NEO4J_USERNAME,
        password=NEO4J_PASSWORD,
        index_name="message-embeddings", 
        embedding_node_property="embedding",
        text_node_property="content"  # Use 'content' based on your schema
    )
except Exception as e:
    print("Error connecting to vectorStore:", e)

# Your search query
try: 
    result = threadr_chat_vector.similarity_search(
        "leku",
        top_k=5
    )
except Exception as e:
    print("Error searching for similar documents:", e)

# Display results
for doc in result:
    try:
        print(doc.page_content)
    except Exception as e:
        print(f"Error displaying document: {e}")
        print(doc)
