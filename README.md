![threadNexus](https://raw.githubusercontent.com/carverauto/threadnexus/main/assets/thread-banner.png)

# Description

Create an opensource social graph tool identifying relationships between actors,
particularly threat actors, creating graphs and clusters. Identify the strength 
of relationships Actor-to-Actor or Actor-to-Cluster.

## Project Goals

* Identify Actors by observing social media, chat rooms, etc.
* Find and Store relationships between Actors
* Assign weights to relationships
* Identify clusters of Actors
* Assign weights to clusters
* Adopt IRC, Slack, Discord, etc.
* Automatic Dossier Creation
* Query LLM/RAG

## Community

Join us on our https://discord.gg/YnzMAJvb

## Embeddings

Chat messages will be run through an embedder or sentence transformer to create vectorizations
and will be saved in a vector index. 

## Graph-RAG

LLMs grounded by knowledge graphs (graph-rag) will be used to answer questions such as
"Does Alice know Bob?"

and "What does Alice know about Bob?"

## Inferring Relationships

### Inferring Relationship Strengths

Like the jibble project, we will use IRC bots to monitor chat rooms and infer relationships between actors. 
We will use the following methods to infer relationships:

* Direct Addressing (e.g. "Hey @carverauto, what do you think?")
* Temporal Proximity (e.g. "I agree with @carverauto's point")
* Temporal Density - How often do two actors interact?

### Semantic Inference using an LLM

LLMs can significantly enhance the inference process by understanding the context, sentiment, and the subtleties of human conversation beyond the capabilities of traditional rule-based systems. 

Scheduled Summarization: Periodically, the system can invoke an LLM to summarize recent conversations. This not only helps in understanding the general discourse but can also highlight recurring themes or subjects around which relationships may form.

Trigger-based Collection: Implement triggers based on conversational cues, such as pauses in dialogue or shifts in topics, to capture and analyze snapshots of conversations. This method ensures that the analysis is contextually relevant and timely.

Interval-based Analysis: Similar to windowing, this involves examining conversations within set intervals to infer relationships and summarize content. This approach can be dynamically adjusted based on the volume of conversation or specific events within the chat room.

#### Leader Selection

Analyze conversation to find conversation leaders or the perceived leader, for many different contexts (primary chat, or within a cluster)

### Challenges

* Nick Changes - How do we track a user who changes their nick? BBB style database?
* Actor Disassociation 
 - How do we handle actors who are not in the same room?
 - How do we handle actors who are in the same room but never interact?
 - How do we handle actors who are in the same room but never interact in a way that we can infer a relationship?
* Private Messages - Unable to infer relationships from private messages w/o access to the messages, could be a future feature.

## Visualizing Relationships

* Spring Embedder - A force directed graph layout algorithm
* Modified Spring Embedder Force Model - A force directed graph layout algorithm with a modified spring embedder

## Temporal Decay

If we are able to infer the strength of relationships, we can use a temporal decay model to reduce the strength of relationships over time.

## Spam Filtering

TBD
