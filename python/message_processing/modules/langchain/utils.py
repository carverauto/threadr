# modules/messages/message_sender.py
from modules.nats.publish_message import publish_message_to_jetstream
from langchain_core.messages import HumanMessage


async def send_response_message(response_message, message_id, subject, stream, channel):
    """
    Sends a response message to a specified channel.
    :param stream:
    :param subject:
    :param message_id:
    :param response_message:
    :param channel:
    :return:
    """
    print("send response message- Message ID: ", message_id)

    print(f"Sending response to {response_message['channel']}: {response_message['response']}")
    # Assuming you're using NATS for messaging
    # Adjust this function to use your messaging system
    await publish_message_to_jetstream(
        subject=subject,
        stream=stream,
        message_id=message_id,
        message_content=response_message["response"],
        channel=channel
    )
    print(f"Response sent to {response_message['channel']}: {response_message['response']}")


def format_graph_output_as_response(graph_output, channel):
    return {
        "channel": channel,
        "response": graph_output
    }

async def execute_graph_with_command(graph, command, message_data):
    initial_state = {"messages": [HumanMessage(content=command)]}
    researcher_messages = []  # List to store messages from the Researcher

    print("Executing graph with command: ", command)

    for state in graph.stream(initial_state, {"recursion_limit": 100}):
        print("State: ", state)
        if "Researcher" in state:
            # Append all researcher messages to the list
            researcher_messages.extend([msg.content for msg in state["Researcher"]["messages"]])
        if "FINISH" in state or state.get("Supervisor", {}).get("next") == "FINISH":
            # At this point, you have all messages from the Researcher
            # Decide how to select the final message. For simplicity, let's concatenate them.
            final_message_content = "\n".join(researcher_messages)
            print("Final message content: ", final_message_content)
            return final_message_content

    print("No final message content found.")
    return None
