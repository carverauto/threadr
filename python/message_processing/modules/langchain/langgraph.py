# modules/langchain/langgraph.py

import operator
from typing import Annotated, Sequence, TypedDict, Dict, Union
import functools

from langchain_community.tools.tavily_search import TavilySearchResults
from langchain_core.messages import BaseMessage, HumanMessage
from langgraph.graph import StateGraph, END
from modules.langchain.langchain import create_agent
from langchain_experimental.tools import PythonREPLTool
from langchain_core.agents import AgentAction, AgentFinish
from langchain_core.messages import BaseMessage
from langchain_core.agents import AgentFinish
from langgraph.prebuilt.tool_executor import ToolExecutor
from langchain_core.agents import AgentActionMessageLog
import operator


class AgentState(TypedDict):
    # The input string
    input: str
    # The list of previous messages in the conversation
    messages: Annotated[Sequence[BaseMessage], operator.add]
    chat_history: list[BaseMessage]
    # The outcome of a given call to the agent
    # Needs `None` as a valid type, since this is what this will start as
    agent_outcome: Union[AgentAction, AgentFinish, None]
    # List of actions and corresponding observations
    # Here we annotate this with `operator.add` to indicate that operations to
    # this state should be ADDED to the existing values (not overwrite it)
    intermediate_steps: Annotated[list[tuple[AgentAction, str]], operator.add]


# Define the agent
def run_agent(data, agent_runnable):
    agent_outcome = agent_runnable.invoke(data)
    return {"agent_outcome": agent_outcome}


# Define the function to execute tools
def execute_tools(data, tool_executor: ToolExecutor):
    # Get the most recent agent_outcome - this is the key added in the `agent` above
    agent_action = data["agent_outcome"]
    output = tool_executor.invoke(agent_action)
    return {"intermediate_steps": [(agent_action, str(output))]}


# Define logic that will be used to determine which conditional edge to go down
def should_continue(data):
    # If the agent outcome is an AgentFinish, then we return `exit` string
    # This will be used when setting up the graph to define the flow
    if isinstance(data["agent_outcome"], AgentFinish):
        return "end"
    # Otherwise, an AgentAction is returned
    # Here we return `continue` string
    # This will be used when setting up the graph to define the flow
    else:
        return "continue"


def first_agent(inputs,tool):
    action = AgentActionMessageLog(
        # We force call this tool
        tool=tool,
        # We just pass in the `input` key to this tool
        tool_input=inputs["input"],
        log="",
        message_log=[],
    )
    return {"agent_outcome": action}


def initialize_graph(llm, tools: Dict[str, object], supervisor_chain, agent_runnable):
    workflow = StateGraph(AgentState)

    # Add the Supervisor node to the graph
    workflow.add_node("Supervisor", lambda state: supervisor_chain.invoke(state))

    # Define a new node that uses agent_runnable
    def agent_runnable_node(state):
        # Assuming state contains the necessary input for agent_runnable
        input_data = state['input']
        result = agent_runnable.invoke(input_data)
        # Process result and decide on next steps
        if result.get('should_finish', False):  # Corrected line
            return {"next": END}
        else:
            # Continue with other actions based on result
            return {"next": "SomeOtherNode", "data": result}

    workflow.add_node("AgentRunnable", agent_runnable_node)

    # Add other nodes and edges as before
    # Example of adding an edge from the supervisor to the agent_runnable node
    workflow.add_edge("Supervisor", "AgentRunnable")

    # Add an edge from the AgentRunnable node to the END node
    workflow.add_edge("AgentRunnable", END)

    # Set the entry point of the graph to the Supervisor node
    workflow.set_entry_point("Supervisor")

    # Define other edges and nodes as necessary
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


