from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_core.prompts import PromptTemplate
from langchain.chains import RetrievalQA
from langchain_community.chat_models import ChatOllama
from langchain_community.vectorstores.neo4j_vector import Neo4jVector
from configs.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD
# import tracemalloc

# tracemalloc.start()

model_name = "sentence-transformers/all-mpnet-base-query"

embedding_model = HuggingFaceEmbeddings(
    model_name=model_name,
)

chat_llm = ChatOllama(
    base_url="http://192.168.1.80:11434",
    model="llama2:chat"
)


rag_template = PromptTemplate(
    template="<s> [INST] You are an observer... </INST]",
    input_variables=["question_string", "context", "question"]
)


def build_retrieval_qa(llm, prompt, vectordb):
    chain_type_kwargs = {"prompt": prompt, "verbose": False}
    dbqa = RetrievalQA.from_chain_type(llm,
                                       chain_type="stuff",
                                       retriever=vectordb,
                                       return_source_documents=True,
                                       chain_type_kwargs=chain_type_kwargs,
                                       verbose=True)
    return dbqa


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
    print(f"Vector Index Dimensions: {threadr_chat_vector.embedding_dimension}")
    retriever = threadr_chat_vector.as_retriever()
    prompt = rag_template.format(question_string="What does leku talk about?")
    dbqa = build_retrieval_qa(llm=chat_llm, prompt=prompt, vectordb=retriever)
    result = dbqa({"question": "Test Query"})
    print(result)
except Exception as e:
    print("Error connecting to vectorStore:", e)
    threadr_chat_vector._driver.close()
