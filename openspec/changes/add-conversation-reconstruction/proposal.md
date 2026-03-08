# Change: Add Probabilistic Conversation Reconstruction

## Why
Threadr can already ingest channel messages and detect some explicit mentions, but that is not enough to reconstruct real conversations in IRC, Discord, or Slack-like systems. Long-running exchanges, delayed answers, nick changes, and multiple parallel discussions in the same room all require a conversation-reconstruction layer between raw chat events and the relationship graph.

## What Changes
- Add a canonical event-history contract that stores every observed channel message plus relevant context events such as nick changes, joins, parts, edits, deletes, reactions, and platform reply metadata.
- Add a conservative identity model that separates canonical actors from aliases and alias observations instead of treating nicknames as durable identity.
- Add a probabilistic conversation-reconstruction pipeline that creates scored message-to-message links, message-to-conversation links, and pending question or task state from multiple signals.
- Add active, dormant, and revived conversation objects that preserve participant, entity, and unresolved-question memory across long gaps.
- Add evidence-backed relationship derivation and analyst QA retrieval based on reconstructed conversations rather than raw message adjacency alone.

## Impact
- Affected specs: `conversation-reconstruction`
- Affected code: IRC and Discord ingest adapters, tenant message and relationship data models, extraction and embedding pipelines, graph projection code, and analyst/query retrieval paths
