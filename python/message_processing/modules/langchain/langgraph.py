# modules/langchain/langgraph.py

import operator
from typing import Annotated, Sequence, TypedDict, Dict
import functools

from langchain_community.tools.tavily_search import TavilySearchResults
from langchain_core.messages import BaseMessage, HumanMessage
from langgraph.graph import StateGraph, END
from modules.langchain.langchain import create_agent
from langchain_experimental.tools import PythonREPLTool


# The agent state is the input to each node in the graph
class AgentState(TypedDict):
    # The annotation tells the graph that new messages will always
    # be added to the current states
    messages: Annotated[Sequence[BaseMessage], operator.add]
    # The 'next' field indicates where to route to next
    next: str


tavily_tool = TavilySearchResults(max_results=5)
python_repl_tool = PythonREPLTool()


def initialize_graph(llm, tools: Dict[str, object], supervisor_chain):
    """
    Initialize the graph for the workflow.
    :param llm:
    :param tools:
    :param supervisor_chain:
    :return:
    """

    # Use tools from the dictionary
    research_agent = create_agent(llm, [tools['TavilySearch']], "You are a web researcher.")
    code_agent = create_agent(llm, [tools['PythonREPL']], "You may generate safe python code.")

    # Define nodes for the graph
    research_node = functools.partial(agent_node, agent=research_agent, name="Researcher")
    code_node = functools.partial(agent_node, agent=code_agent, name="Coder")

    # Initialize and configure the workflow graph
    workflow = StateGraph(AgentState)
    workflow.add_node("Researcher", research_node)
    workflow.add_node("Coder", code_node)
    workflow.add_node("Supervisor", supervisor_chain)

    members = ["Researcher", "Coder"]
    for member in members:
        workflow.add_edge(member, "Supervisor")

    conditional_map = {k: k for k in members}
    conditional_map["FINISH"] = END
    workflow.add_conditional_edges("Supervisor", lambda x: x["next"], conditional_map)
    workflow.set_entry_point("Supervisor")

    return workflow.compile()


def agent_node(state, agent, name):
    """
    Function to process an agent node in the graph.
    :param state:
    :param agent:
    :param name:
    :return:
    """
    result = agent.invoke(state)
    return {"messages": [HumanMessage(content=result["output"], name=name)]}


