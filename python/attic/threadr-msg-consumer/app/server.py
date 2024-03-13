from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from langserve import add_routes
from neo4j_semantic_layer import agent_executor as neo4j_semantic_layer_chain


app = FastAPI()


@app.get("/")
async def redirect_root_to_docs():
    return RedirectResponse("/docs")


# Edit this to add the chain you want to add
add_routes(app, neo4j_semantic_layer_chain, path="/neo4j-semantic-layer")

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
