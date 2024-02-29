from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain.chains import RetrievalQA
from langchain_community.chat_models import ChatOllama
from langchain_community.vectorstores.neo4j_vector import Neo4jVector
from configs.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD
# import tracemalloc

# tracemalloc.start()

model_name = "sentence-transformers/all-mpnet-base-v2"

embedding_model = HuggingFaceEmbeddings(
    model_name=model_name,
)

chat_llm = ChatOllama(
    base_url="http://192.168.1.80:11434",
    model="llama2:chat"
)

try:
    threadr_chat_vector = Neo4jVector.from_existing_index(
        embedding=embedding_model,
        url=NEO4J_URI,
        username=NEO4J_USERNAME,
        password=NEO4J_PASSWORD,
        index_name="message-embeddings",
        node_label="Message",
        embedding_node_property="embedding",
        text_node_property="content"
    )
    print(threadr_chat_vector.embedding_dimension)
    """
    chat_retriever = RetrievalQA.from_llm(
        llm=chat_llm,
        retriever=threadr_chat_vector.as_retriever(),
        verbose=True
    )
    """
    # prompt should be a dict
    prompt = {
        "text": "who is john galt?",
        "context": "John Galt is a character in Ayn Rand's novel Atlas Shrugged (1957). Although he is not identified by name until the last third of the novel, he is the object of its often-repeated question 'Who is John Galt?' and of the quest to discover the answer."
    }
    qa_chain = RetrievalQA.from_chain_type(chat_llm, 
                                           retriever=threadr_chat_vector.as_retriever(),
                                           chain_type="stuff",
                                           )

    qa_chain({"question": "who is john leku?"}, return_only_outputs=True)


except Exception as e:
    print("Error connecting to vectorStore:", e)
    threadr_chat_vector._driver.close()
