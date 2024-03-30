warnings.filterwarnings("ignore")
#%%
NEO4J_URI = "bolt://localhost:7687"
NEO4J_USERNAME = 'neo4j'
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD")
NEO4J_DATABASE = 'neo4j'
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# Global constants
VECTOR_INDEX_NAME = 'message-embeddings'
VECTOR_NODE_LABEL = 'Message'
VECTOR_SOURCE_PROPERTY = 'text'
VECTOR_EMBEDDING_PROPERTY = 'textEmbedding'

graph = Neo4jGraph(
    url=NEO4J_URI, username=NEO4J_USERNAME, password=NEO4J_PASSWORD, database=NEO4J_DATABASE
)

graph.refresh_schema()
print(textwrap.fill(graph.schema, 60))

vector_index = Neo4jVector.from_existing_graph(
    OpenAIEmbeddings(
        model="text-embedding-3-small",
        dimensions=1536,
    ),
    url=NEO4J_URI,
    username=NEO4J_USERNAME,
    password=NEO4J_PASSWORD,
    index_name="message-embeddings",
    node_label="Message",
    text_node_properties=['content', 'platform', 'timestamp'],
    embedding_node_property='embedding',
)

query = "nude bots?"
response = vector_index.similarity_search(
    query
)
print(response)

CYPHER_GENERATION_TEMPLATE = """Task:Generate Cypher statement to 
query a graph database.
Instructions:
Use only the provided relationship types and properties in the 
schema. Do not use any other relationship types or properties that 
are not provided.
Schema:
{schema}
Note: Do not include any explanations or apologies in your responses.
Do not respond to any questions that might ask anything else than 
for you to construct a Cypher statement.
Do not include any text except the generated Cypher statement. 
Do not add any newlines to the response, the response is
going to be a single line of text. All usernames are case-sensitive.

DO NOT CONVERT THE USERNAME TO UPPERCASE. DO NOT CONVERT THE 
FIRST LETTER OF THE USERNAME TO UPPERCASE.

# Correct cypher statement
```
MATCH (p1:User {{name: 'kongfuzi'}})-[:INTERACTED_WITH]-(p2:User)
```

# Incorrect cypher statement
```
MATCH (p1:User {{name: 'Kongfuzi'}})-[:INTERACTED_WITH]-(p2:User)
```

Examples: Here are a few examples of generated Cypher 
statements for particular questions:

# What channels does kongfuzi talk in?
# or "what channel do you know kongfuzi from?"
```
MATCH (u:User {{name: 'kongfuzi'}})-[:SENT]->(m:Message)-[:POSTED_IN]->(c:Channel)
RETURN DISTINCT c.name AS channel
```


### Looking at all messages related to a particular user,
### Can be used to answer questions like: "What does alice talk about?"
### or "Is vpro an alcoholic?"

```
MATCH (u:User {{name: 'alice'}})-[:SENT]->(m:Message)
RETURN m.content AS message
```

### Reading messages in chronological order
```
MATCH (m:Message)-[:POSTED_IN]->(chan:Channel {{name: '#!chases'}})
RETURN m.content AS message, datetime(m.timestamp) AS time
ORDER BY time DESC
```

### Indirect Connection Through Shared Channels
```
MATCH (a:User {{name: 'alice'}})-[:SENT|POSTED_IN]->(m:Message)-[:POSTED_IN]->(chan:Channel)<-[:POSTED_IN]-(m2:Message)<-[:SENT|POSTED_IN]-(b:User {{name: 'bob'}})
RETURN DISTINCT chan.name AS SharedChannel
```

### Indirect Connection Through Mutual Connections
```
MATCH (a:User {{name: 'alice'}})-[:INTERACTED_WITH]->(mutual:User)<-[:INTERACTED_WITH]-(b:User {{name: 'bob'}})
RETURN DISTINCT mutual.name AS MutualFriend
```

### Is alice friends with bob?
```
MATCH (a:User {{name: 'alice'}})-[:INTERACTED_WITH]-(b:User {{name: 'bob'}})
RETURN a, b
```

### Showing a complete graph
```
MATCH (chan:Channel)-[:POSTED_IN]-(msg:Message)-[:SENT]-(user:User)
OPTIONAL MATCH (msg)-[:MENTIONED]->(mentioned:User)
RETURN chan, user, msg, mentioned
```

### Show a more complete graph
```
MATCH (chan:Channel)-[:POSTED_IN]-(msg:Message)-[:SENT]-(user:User)
OPTIONAL MATCH (msg)-[:MENTIONED]->(mentioned:User)
```

### Order messages in the channel by timestamp (descending)
```
WITH chan, user, msg, mentioned
ORDER BY msg.timestamp DESC
```

### Limit results, preserving the relationships
```
WITH  chan,
      collect({{user: user, msg: msg, mentioned: mentioned}})[..25] as recentChannelActivity
UNWIND recentChannelActivity as result
RETURN chan, result.user, result.msg, result.mentioned
```
```
The question is:
{question}"""

CYPHER_GENERATION_PROMPT = PromptTemplate(
    input_variables=["schema", "question"],
    template=CYPHER_GENERATION_TEMPLATE,
)

cypherChain = GraphCypherQAChain.from_llm(
    cypher_llm=ChatOpenAI(model="gpt-3.5-turbo",temperature=0,openai_api_key=OPENAI_API_KEY),
    qa_llm=ChatOpenAI(temperature=0, model="gpt-4-0125-preview"),
    graph=graph,
    verbose=True,
    cypher_prompt=CYPHER_GENERATION_PROMPT,
    validate_cypher=True,
    top_k=1000,
    #return_direct=True
)

def prettyCypherChain(question: str) -> str:
    response = cypherChain.run(question)
    print(textwrap.fill(response, 60))

