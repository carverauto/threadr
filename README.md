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

## Inferring Relationships

### Inferring Relationship Strengths

Like the jibble project, we will use IRC bots to monitor chat rooms and infer relationships between actors. 
We will use the following methods to infer relationships:

* Direct Addressing (e.g. "Hey @carverauto, what do you think?")
* Temporal Proximity (e.g. "I agree with @carverauto's point")
* Temporal Density - How often do two actors interact?

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