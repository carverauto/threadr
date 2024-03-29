# modules/messages/message_sender.py
from modules.nats.publish_message import publish_message_to_jetstream
from langchain_core.messages import HumanMessage


async def send_response_message(response_message):
    # Assuming you're using NATS for messaging
    # Adjust this function to use your messaging system
    await publish_message_to_jetstream(
        subject="response",  # Adjust as necessary
        stream="responses",  # Adjust as necessary
        message_id="unique_id",  # Generate or obtain a unique ID for the message
        message_content=response_message["response"]
    )
    print(f"Response sent to {response_message['channel']}: {response_message['response']}")


def format_graph_output_as_response(graph_output, channel):
    return {
        "channel": channel,
        "response": graph_output
    }


async def execute_graph_with_command(graph, command, message_data):
    """
    Executes the graph based on a given command and initial message data.

    Args:
        graph: The graph object to be executed.
        command: The extracted command from the message.
        message_data: The original message data received.

    Returns:
        A string representing the collective output from the graph execution.
    """
    # Prepare the initial state for the graph based on the command
    initial_state = {
        "messages": [HumanMessage(content=command)]
    }

    # Execute the graph and collect the output
    graph_output = []
    for state in graph.stream(initial_state, {"recursion_limit": 100}):
        if "__end__" not in state:
            # Here, you might want to format or process each piece of output
            # For simplicity, we're just collecting the outputs
            graph_output.append(state)
        else:
            break

    # Format the collected output into a single string or structured data
    # Depending on your needs, you might format it differently
    formatted_output = "\n".join([str(output) for output in graph_output])

    return formatted_output
