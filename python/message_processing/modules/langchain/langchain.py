# modules/langchain/langchain.py

from langchain.agents import AgentExecutor, create_openai_tools_agent
from langchain_core.messages import BaseMessage, HumanMessage
from langchain.chat_models import ChatOpenAI
from langchain.chains import RetrievalQAWithSourcesChain, ConversationalRetrievalChain
from langchain.memory import ConversationBufferMemory
from langchain.output_parsers.openai_functions import JsonOutputFunctionsParser
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder


# Agent Supervisor
# Will use function calling to choose the next worker node
# OR finish processing.
def create_supervisor(llm):
    """
    Function to create an agent supervisor.
    :param llm:
    :return:
    """
    members = ["Researcher", "Coder"]
    system_prompt = (
        "You are a supervisor tasked with managing a conversation between the"
        " following workers:  {members}. Given the following user request,"
        " respond with the worker to act next. Each worker will perform a"
        " task and respond with their results and status. When finished,"
        " respond with FINISH."
    )
    # Our team supervisor is an LLM node. It just picks the next agent to process
    # and decides when the work is completed
    options = ["FINISH"] + members
    # Using openai function calling can make output parsing easier for us
    function_def = {
        "name": "route",
        "description": "Select the next role.",
        "parameters": {
            "title": "routeSchema",
            "type": "object",
            "properties": {
                "next": {
                    "title": "Next",
                    "anyOf": [
                        {"enum": options},
                    ],
                }
            },
            "required": ["next"],
        },
    }
    prompt = ChatPromptTemplate.from_messages(
        [
            ("system", system_prompt),
            MessagesPlaceholder(variable_name="messages"),
            (
                "system",
                "Given the conversation above, who should act next?"
                " Or should we FINISH? Select one of: {options}",
            ),
        ]
    ).partial(options=str(options), members=", ".join(members))

    # Return the supervisor chain
    return (
        prompt
        | llm.bind_functions(functions=[function_def], function_call="route")
        | JsonOutputFunctionsParser()
    )


def create_agent(llm: ChatOpenAI, tools: list, system_prompt: str):
    """
    Creates an agent with specified tools and a system prompt.

    Args:
        llm (ChatOpenAI): The language model to use for the agent.
        tools (list): A list of tools the agent can use.
        system_prompt (str): The system prompt that guides the agent's behavior.

    Returns:
        AgentExecutor: An executor that manages the agent's execution.
    """
    # Each worker node will be given a name and some tools.
    prompt = ChatPromptTemplate.from_messages(
        [
            (
                "system",
                system_prompt,
            ),
            MessagesPlaceholder(variable_name="messages"),
            MessagesPlaceholder(variable_name="agent_scratchpad"),
        ]
    )
    agent = create_openai_tools_agent(llm, tools, prompt)
    executor = AgentExecutor(agent=agent, tools=tools)
    return executor


def agent_node(state, agent, name):
    """
    Function to execute the agent on a given state.
    :param state:
    :param agent:
    :param name:
    :return:
    """

    result = agent.invoke(state)
    return {"messages": [HumanMessage(content=result["output"], name=name)]}


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