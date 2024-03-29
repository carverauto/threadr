# modules/messages/message_sender.py
from modules.nats.publish_message import publish_message_to_jetstream
from langchain_core.messages import HumanMessage


async def send_response_message(response_message, message_id, subject, stream):
    """
    Sends a response message to a specified channel.
    :param stream:
    :param subject:
    :param message_id:
    :param response_message:
    :return:
    """
    print(f"Sending response to {response_message['channel']}: {response_message['response']}")
    # Assuming you're using NATS for messaging
    # Adjust this function to use your messaging system
    await publish_message_to_jetstream(
        subject=subject,
        stream=stream,
        message_id=message_id,
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

    final_message_content = None

    for state in graph.stream(initial_state, {"recursion_limit": 100}):
        print(state)
        if "FINISH" in state:
            # Assuming the final message is in the last state before "__end__"
            # and that it's structured as shown in your sample output
            final_message_content = state.get("messages", [{}])[-1].get("content", "")
            break

    return final_message_content
