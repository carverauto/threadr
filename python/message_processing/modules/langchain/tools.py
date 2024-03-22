from langchain.tools import Tool
from langchain_community.vectorstores.neo4j_vector import Neo4jVector
from langchain_openai import OpenAIEmbeddings
from langchain.prompts.prompt import PromptTemplate
from langchain.chains import GraphCypherQAChain
from langchain_openai import ChatOpenAI
from modules.environment.settings import NEO4J_URI, NEO4J_PASSWORD
import textwrap
from modules.cloudevents.cypher_templates import CYPHER_GENERATION_TEMPLATE
from langchain_community.graphs import Neo4jGraph


def create_tools(neo4j_adapter):
    # Define your custom tools here

    graph = Neo4jGraph(url=NEO4J_URI, username="neo4j", password=NEO4J_PASSWORD,
                       database="neo4j")

    def run_cypher_query(query):
        # Implement the logic to run a Cypher query using neo4j_adapter
        # refresh the graph
        graph.refresh_schema()
        print(textwrap.fill(graph.schema, 60))

        CYPHER_GENERATION_PROMPT = PromptTemplate(
            input_variables=["schema", "question"],
            template=CYPHER_GENERATION_TEMPLATE,
        )

        cypherChain = GraphCypherQAChain.from_llm(
            cypher_llm=ChatOpenAI(model="gpt-3.5-turbo", temperature=0),
            qa_llm=ChatOpenAI(temperature=0, model="gpt-4-0125-preview"),
            graph=graph,
            verbose=True,
            cypher_prompt=CYPHER_GENERATION_PROMPT,
            # validate_cypher=True,
            top_k=2000,
        )

        response = cypherChain(query)
        return response['result']

    def perform_vector_similarity_search(query, message):
        # Implement the logic to perform vector similarity search using neo4j_adapter
        vector_index = Neo4jVector.from_existing_graph(
            OpenAIEmbeddings(
                model="text-embedding-3-small",
                dimensions=1536,
            ),
            url=NEO4J_URI,
            username="neo4j",
            password=NEO4J_PASSWORD,
            index_name="message-embeddings",
            node_label="Message",
            text_node_properties=['content', 'platform', 'timestamp'],
            embedding_node_property="embedding",
        )

        response = vector_index.similarity_search(
            query=message.message,
        )
        print(response)
        return response

    tools = [
        Tool(
            name="CypherQuery",
            func=run_cypher_query,
            description="Run a custom Cypher query on the Neo4j database",
        ),
        Tool(
            name="VectorSimilaritySearch",
            func=perform_vector_similarity_search,
            description="Perform vector similarity search on the Neo4j database",
        ),
        # Add more custom tools as needed
    ]

    return tools