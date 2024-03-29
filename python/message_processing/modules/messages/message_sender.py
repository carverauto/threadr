# modules/messages/message_sender.py
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
