# ./query/modules/langchain/langchain.py

from langchain_community.chat_models import ChatOpenAI
from langchain.chains import RetrievalQAWithSourcesChain, ConversationalRetrievalChain
from modules.neo4j.graph_memory import GraphMemory


def initialize_qa_workflow(neo4j_vector, openai_api_secret_key):
    """Function to set up the question-answer workflow using LangChain."""

    chain = RetrievalQAWithSourcesChain.from_chain_type(
        ChatOpenAI(temperature=0, openai_api_key=openai_api_secret_key),
        chain_type="stuff",
        retriever=neo4j_vector.as_retriever(),
    )

    return chain


def execute_qa_workflow(neo4j_vector, qa_workflow, query, openai_api_secret_key, neo4j_credentials):
    """Function to execute the QA workflow and retrieve the answers."""

    # Execute the QA workflow
    qa_workflow(
        {"question": query},
        return_only_outputs=True,
    )

    # Create an instance of GraphMemory
    memory = GraphMemory(
        neo4j_url=neo4j_credentials["url"],
        neo4j_username=neo4j_credentials["username"],
        neo4j_password=neo4j_credentials["password"],
    )

    # Create a ConversationalRetrievalChain with GraphMemory
    qa = ConversationalRetrievalChain.from_llm(
        ChatOpenAI(temperature=0, openai_api_key=openai_api_secret_key),
        retriever=neo4j_vector.as_retriever(),
        memory=memory,
    )

    # Execute the ConversationalRetrievalChain
    results = qa({"question": query})

    return results