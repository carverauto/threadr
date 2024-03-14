from langchain_community.vectorstores.neo4j_vector import Neo4jVector
from langchain_community.embeddings import HuggingFaceEmbeddings


def initialize_neo4j_vector(credentials, index_name):
    """
    Function to instantiate a Neo4j vector from an existing vector.
    """
    # Neo4j Aura credentials
    url = credentials["url"]
    username = credentials["username"]
    password = credentials["password"]

    # Model name for HuggingFace embeddings
    model_name = "sentence-transformers/all-mpnet-base-v2"

    # Instantiate HuggingFace embeddings model
    embedding_model = HuggingFaceEmbeddings(model_name=model_name)

    # Instantiate Neo4j vector from an existing vector
    neo4j_vector = Neo4jVector.from_existing_index(
        embedding=embedding_model,
        url=url,
        username=username,
        password=password,
        index_name=index_name,
    )

    return neo4j_vector


def perform_similarity_search(neo4j_vector, query):
    """
    Function to perform a vector similarity search.
    """
    # Implement the actual logic using the langchain module's similarity_search method
    try:
        results = neo4j_vector.similarity_search(query)
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
    return results