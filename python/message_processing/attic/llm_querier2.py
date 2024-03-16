from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain.prompts import ChatPromptTemplate
from langchain.chains import RetrievalQA
from langchain_community.chat_models import ChatOllama
from langchain_community.vectorstores.neo4j_vector import Neo4jVector
from langchain_core.runnables import RunnableLambda, RunnablePassthrough
from langchain_core.output_parsers import StrOutputParser
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


def get_relevant_documents(query, retriever):
    results = retriever.similarity_search(query)  # Assuming this works correctly
    return [doc.page_content for doc in results]  # Extract text content


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
    template = """Answer the question based on on the following context:
    {context}

    Question: {question}
    """
    prompt = ChatPromptTemplate.from_template(template)
    chain = (
        {"context": retriever, "question": RunnablePassthrough()}
        | prompt
        | chat_llm
        | StrOutputParser()
    )

    result = chain.invoke("Where is the hedwig?")
    print(result)
except Exception as e:
    print("Error connecting to vectorStore:", e)
    threadr_chat_vector._driver.close()
