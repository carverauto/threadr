from abc import ABC

from langchain.chains.graph_qa.cypher import GraphCypherQAChain
from langchain_core.callbacks import CallbackManagerForToolRun
from langchain_core.tools import BaseTool
from langchain_core.pydantic_v1 import BaseModel, Field
from typing import Dict, Optional, Type, Union, Any


class CypherQueryInput(BaseModel):
    """Input for generating Cypher queries."""
    question: str = Field(description="Natural language question to generate a Cypher query for")


class CypherQueryTool(BaseTool):
    """Tool that generates and validates Cypher queries using language models."""
    name: str = "cypher_query_generator"
    description: str = "Generates and validates Cypher queries based on natural language input."
    cypher_chain: GraphCypherQAChain
    args_schema: Type[BaseModel] = CypherQueryInput

    def __init__(self, cypher_chain: GraphCypherQAChain, **kwargs: Any):
        print(f"Initializing CypherQueryTool with cypher_chain: {cypher_chain}")
        print(f"kwargs before super().__init__: {kwargs}")
        super().__init__(cypher_chain=cypher_chain, **kwargs)
        # super().__init__(**kwargs)
        self.cypher_chain = cypher_chain

    def _run(self, question: str, run_manager: Optional[CallbackManagerForToolRun] = None) -> Union[str, Dict]:
        """Synchronously generate and validate a Cypher query based on a question."""
        try:
            # Synchronous call to generate the query
            response = self.cypher_chain.run(question)
            return response
        except Exception as e:
            error_message = f"Failed to generate Cypher query: {str(e)}"
            return {"error": error_message}

    async def _arun(
            self,
            question: str,
            run_manager: Optional[CallbackManagerForToolRun] = None,
    ) -> Union[str, Dict]:
        """Generate and validate a Cypher query based on a question asynchronously."""
        try:
            response = await self.cypher_chain.run(question)
            return response
        except Exception as e:
            error_message = f"Failed to generate Cypher query: {str(e)}"
            return {"error": error_message}

    # If you need an asynchronous version, you would adapt this method accordingly.
