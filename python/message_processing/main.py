import uvicorn
from fastapi import FastAPI
from modules.neo4j.neo4j_adapter import Neo4jAdapter
from modules.cloudevents import cloudevents_handler as handler
from modules.environment.settings import NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD, NATS_URL, NKEYSEED, USE_QUEUE_GROUP, \
    OPENAI_API_KEY
from modules.messages.message_processor import MessageProcessor
from modules.nats.nats_manager import NATSManager
from modules.nats.nats_consumer import NATSConsumer
from modules.nats.nats_producer import NATSProducer


app = FastAPI(debug=True)

@app.get("/extract_command")
async def get_extract_command():
    return handler.extract_command_from_message("threadr: What is threadr about?")

@app.post("/extract_command")
async def post_extract_command(message: str):
    return handler.extract_command_from_message(message)

@app.post("/process_message")
async def post_extract_command(message):
    neo4j_adapter = Neo4jAdapter(uri=NEO4J_URI, username=NEO4J_USERNAME, password=NEO4J_PASSWORD)

    # Connect to Neo4j
    await neo4j_adapter.connect()


    nats_manager = NATSManager(NATS_URL, NKEYSEED)

    await nats_manager.connect()

    # Initialize the producer
    producer = NATSProducer(nats_manager)

    # Initialize the LLM
    # llm = ChatOpenAI(temperature=0, openai_api_key=OPENAI_API_KEY, model_name="gpt-4-0125-preview")

    message_processor = MessageProcessor(neo4j_adapter=neo4j_adapter, producer=producer)
    await message_processor.process_message_direct(message)

uvicorn.run(app)
