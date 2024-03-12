from langchain.chat_models import ChatOpenAI
from langchain.chains import RetrievalQAWithSourcesChain, ConversationalRetrievalChain
from langchain.memory import ConversationBufferMemory


def initialize_qa_workflow(neo4j_vector, openai_api_secret_key):
    """
    Function to set up the question-answer workflow using LangChain.
    """
    # Implement the actual logic using the langchain modules here
    chain = RetrievalQAWithSourcesChain.from_chain_type(
        ChatOpenAI(temperature=0, openai_api_key=openai_api_secret_key),
        chain_type="stuff",
        retriever=neo4j_vector.as_retriever(),
    )

    return chain


def execute_qa_workflow(neo4j_vector, qa_workflow, query, openai_api_secret_key):
    """
    Function to execute the QA workflow and retrieve the answers.
    """
    # Implement the actual logic using the qa_workflow
    qa_workflow(
        {"question": query},
        return_only_outputs=True,
    )

    memory = ConversationBufferMemory(memory_key="chat_history", return_messages=True)
    qa = ConversationalRetrievalChain.from_llm(
        ChatOpenAI(temperature=0, openai_api_key=openai_api_secret_key),
        neo4j_vector.as_retriever(),
        memory=memory,
    )
    # results = qa({"question": query})["answer"]
    results = qa({"question": query})

    return results
