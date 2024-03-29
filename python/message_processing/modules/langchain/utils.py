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
    print("send response message- Message ID: ", message_id)

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
    initial_state = {"messages": [HumanMessage(content=command)]}
    final_message_content = ""

    for state in graph.stream(initial_state, {"recursion_limit": 100}):
        if "FINISH" in state or state.get("Supervisor", {}).get("next") == "FINISH":
            messages = state.get("messages", [])
            if messages:
                # Concatenate all messages into a single response
                final_message_content = "\n".join([msg.content for msg in messages])
            break

    return final_message_content
