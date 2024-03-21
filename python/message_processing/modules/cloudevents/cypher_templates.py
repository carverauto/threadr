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
Examples: Here are a few examples of generated Cypher 
statements for particular questions:

### Looking at all messages related to a particular user,
### Can be used to answer questions like: "What does Alice talk about?
```
MATCH (u:User {{name: 'bysin'}})-[:SENT]->(m:Message)
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
MATCH (a:User {{name: 'Alice'}})-[:SENT|POSTED_IN]->(m:Message)-[:POSTED_IN]->(chan:Channel)<-[:POSTED_IN]-(m2:Message)<-[:SENT|POSTED_IN]-(b:User {{name: 'Bob'}})
RETURN DISTINCT chan.name AS SharedChannel
```

### Indirect Connection Through Mutual Connections
```
MATCH (a:User {{name: 'Alice'}})-[:INTERACTED_WITH]->(mutual:User)<-[:INTERACTED_WITH]-(b:User {{name: 'Bob'}})
RETURN DISTINCT mutual.name AS MutualFriend
```

### Is Alice friends with Bob?
MATCH (a:User {{name: 'Alice'}})-[:INTERACTED_WITH]-(b:User {{name: 'Bob'}})
RETURN a, b

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

// Order messages in the channel by timestamp (descending)
WITH chan, user, msg, mentioned
ORDER BY msg.timestamp DESC

// Limit results, preserving the relationships
WITH  chan,
      collect({{user: user, msg: msg, mentioned: mentioned}})[..25] as recentChannelActivity
UNWIND recentChannelActivity as result
RETURN chan, result.user, result.msg, result.mentioned
```
The question is:
{question}"""