# modules/langchain/tools.py

from langchain.tools import Tool
from langchain_community.vectorstores.neo4j_vector import Neo4jVector
from langchain_openai import OpenAIEmbeddings
from langchain.prompts.prompt import PromptTemplate
from langchain.chains import GraphCypherQAChain
from langchain_openai import ChatOpenAI
from modules.environment.settings import NEO4J_URI, NEO4J_PASSWORD
from modules.cloudevents.cypher_templates import CYPHER_GENERATION_TEMPLATE
from langchain_community.graphs import Neo4jGraph
from langchain_community.tools.tavily_search import TavilySearchResults
from langchain_experimental.tools import PythonREPLTool
from modules.langchain.cypherquery import CypherQueryTool, CypherQueryInput

def create_tools(neo4j_adapter):
    """
    Create tools for the LangChain.
    :param neo4j_adapter:
    :return:
    """
    graph = Neo4jGraph(url=NEO4J_URI, username="neo4j", password=NEO4J_PASSWORD, database="neo4j")
    graph.refresh_schema()

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
        validate_cypher=True,
        top_k=2000,
    )

    # Instantiate the CypherQueryTool with the cypherChain
    cypher_query_tool = CypherQueryTool(cypher_chain=cypherChain)

    async def run_cypher_query(question):
        """
        Generate and run a Cypher query based on a natural language question.
        :param question: Natural language question
        :return: Cypher query result
        """
        input_data = CypherQueryInput(question=question)
        response = await cypher_query_tool._arun(question=input_data.question)
        return response

    # The rest of your function remains unchanged
    # Initialize the other tools
    tavily_tool = TavilySearchResults(max_results=5)
    python_repl_tool = PythonREPLTool()

    # Return a dictionary of initialized tools
    return {
        'CypherQuery': cypher_query_tool,
        # 'VectorSimilaritySearch': perform_vector_similarity_search,
        'TavilySearch': tavily_tool,
        'PythonREPL': python_repl_tool,
    }
