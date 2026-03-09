## Context
Threadr's stated goal is to infer relationships from chat systems and answer graph-aware questions such as "what did alice talk about with bob last week?" The current repository already stores normalized messages, extracted entities and facts, and embeddings, but the existing inference model is still close to "message implies relationship" with explicit mentions carrying most of the weight.

That approach breaks down in common chat patterns:
- a directly addressed question continues for several turns without repeated mentions
- a user answers days later without using a platform reply feature
- several unrelated sub-conversations happen in the same busy channel
- IRC nicknames change and the graph starts treating aliases as separate people
- analysts need evidence for inferred relationships instead of opaque top-level claims

## Goals
- Preserve a complete tenant-scoped event history for public channel activity and relevant context changes.
- Model identity separately from display nicknames and alias history.
- Reconstruct conversations with confidence-scored links instead of relying only on explicit mentions or adjacency.
- Keep conversation state alive long enough to support delayed replies, unresolved questions, and multi-day discussions.
- Derive actor relationships and analyst answers from conversation objects with supporting evidence.

## Non-Goals
- Fully automated high-confidence identity merges across ambiguous IRC users in the first pass.
- Private-message inference without explicit access to those messages.
- Using an LLM as the primary real-time thread tracker for every inbound message.
- Forcing every message into a conversation when evidence is weak or ambiguous.

## Decisions
- Decision: Store raw channel events first, then infer conversations from that immutable history.
  Reason: Reconstruction quality depends on replayable source data, and inference logic will evolve over time.

- Decision: Keep canonical message history separate from graph projections.
  Reason: Threadr already has tenant-scoped relational history in Elixir and graph-oriented workflows elsewhere; a canonical history lets the system recompute graph edges without losing provenance.

- Decision: Model conversation links as scored hypotheses with evidence.
  Reason: Chat replies are often ambiguous, especially in busy rooms and after long delays.

- Decision: Use a two-stage pipeline.
  Reason: deterministic online scoring is needed for throughput and explainability, while slower batch jobs can summarize clusters, resolve ambiguities, and recalculate weights.

- Decision: Maintain active conversation state with dormancy and revival.
  Reason: delayed answers and status updates cannot be recovered from adjacency windows alone.

- Decision: Use LLMs only for bounded arbitration and summarization.
  Reason: LLMs are valuable for choosing among a few plausible candidates or summarizing a conversation, but they are too expensive and inconsistent as the sole hot-path threader.

## Proposed Model
The change introduces a middle layer:

`raw events -> candidate links -> conversation objects -> semantic facts -> relationship graph -> QA`

### Canonical records
- `Actor`: canonical tenant-scoped identity
- `Alias`: nick or handle value
- `AliasObservation`: alias seen on a platform/channel/time range
- `Message`: immutable normalized message event
- `ContextEvent`: join, part, quit, nick change, edit, delete, reaction, topic change, or other room context
- `Conversation`: active, dormant, or closed conversation state
- `PendingItem`: unresolved question, request, task, or incident query
- `MessageLink`: scored edges such as `RESPONDS_TO`, `REFERENCES`, or `SAME_TOPIC_AS`
- `ConversationMembership`: scored message-to-conversation and actor-to-conversation participation

## Contract Definitions

### Canonical public-channel event contract
The first implementation should extend the current tenant-scoped `Message`, `Actor`, and `Channel` model rather than introduce a separate opaque event store first. The reconstruction contract is defined by immutable message rows plus append-only context records and richer normalized metadata.

#### Message event contract
Every persisted public-channel message event should expose:
- tenant scope, platform, channel, and observed timestamp
- stable platform event identifiers:
  `external_id`, platform message id, platform reply id, platform thread id, and platform conversation id when available
- actor-at-observation-time fields:
  canonical actor id, observed handle, observed display name, and platform account id if available
- immutable content fields:
  raw body, normalized body, attachments, embeds, links, quoted text, mentions, and raw provider payload
- event-shape metadata:
  source subject, ingest correlation id, edit tombstone pointer, delete tombstone pointer, and reaction summary
- enrichment references:
  extraction id, embedding model ids, dialogue-act label, and reconstruction version

The `Message` row remains immutable for original authorship and observed body. Later edits or deletes are represented by append-only context records that reference the original message event.

#### Context event contract
Threadr should store non-message context events as first-class records with:
- `event_type`
- tenant scope
- platform
- channel or room identifier when applicable
- actor id or alias observation id when applicable
- observed timestamp
- external platform event id
- raw payload
- normalized metadata map

The initial supported `event_type` set should include:
- `nick_change`
- `join`
- `part`
- `quit`
- `topic_change`
- `message_edit`
- `message_delete`
- `reaction_add`
- `reaction_remove`
- `thread_state`
- `presence_snapshot`

Each context event must reference the affected message, alias, actor, or channel when that relation exists, but it must not rewrite prior message rows in place.

#### Normalized metadata contract
Normalized metadata should be stable across IRC and Discord even when the raw payloads differ. The first-pass normalized keys should include:
- `reply_to_external_id`
- `thread_external_id`
- `conversation_external_id`
- `quoted_external_ids`
- `attachment_refs`
- `link_refs`
- `reaction_summary`
- `mentioned_handles`
- `mentioned_actor_ids`
- `observed_handle`
- `observed_display_name`
- `platform_account_id`
- `edited_at`
- `deleted_at`
- `presence_state`

Platform-specific extras can remain in the raw payload, but reconstruction logic should depend on normalized keys where possible.

### Actor, alias, and alias-observation contract
The current `Actor` resource should remain the canonical tenant-scoped identity record. Conversation reconstruction adds two new concepts around it.

#### Alias contract
`Alias` represents a platform-scoped handle or display identity string, not a durable person assertion. An alias record should include:
- tenant scope
- platform
- alias value
- normalized alias value
- alias kind:
  `handle`, `display_name`, `thread_display_name`, `system_name`
- first observed timestamp
- last observed timestamp
- status:
  `active`, `historical`, `suppressed`

Alias rows may optionally point at a canonical actor, but the alias itself is not proof that the actor identity is correct forever.

#### Alias observation contract
`AliasObservation` is the immutable evidence that a specific alias was seen in a specific place and time. Each observation should include:
- alias id
- actor id if the ingest event could safely resolve one at observation time
- platform account id if available
- channel id when applicable
- source event type:
  `message`, `nick_change`, `join`, `part`, `presence`, `thread_event`
- source event id
- observed timestamp
- confidence
- raw metadata describing the evidence

Alias observations are the audit trail that later merge or split logic relies on. The system should prefer creating a new alias observation over mutating historical actor identity.

#### Conservative merge rules
The first pass should apply the following merge rules:
- exact platform account ids can attach new alias observations to an existing actor
- explicit platform-native identity continuity such as a Discord author id can reuse the same actor
- IRC nick changes create alias observations and may link aliases, but they do not automatically rewrite historical messages to a different actor without supporting continuity evidence
- repeated co-presence, topic overlap, or writing style similarity alone are not enough to auto-merge actors
- low-confidence continuity evidence must remain reviewable metadata rather than silently changing canonical actor ownership

### Message-link, conversation, membership, and pending-item evidence contract
Reconstruction records should be evidence-bearing hypotheses, not hidden classifier outputs.

#### Message link contract
`MessageLink` should represent a scored relation between two messages with:
- source message id
- target message id
- link type:
  `replies_to`, `continues`, `references`, `same_topic_as`, `clarifies`, `answers`
- score
- confidence band:
  `high`, `medium`, `low`
- winning decision version
- competing candidate margin
- evidence array
- inferred_at
- inferred_by:
  model or ruleset version

Each evidence item should capture:
- `kind`
- `weight`
- `value`
- `explanation`
- optional referenced entity, alias, or message ids

#### Conversation contract
`Conversation` should represent a tenant-scoped reconstructed discussion with:
- stable conversation id
- platform and channel scope
- lifecycle state:
  `active`, `dormant`, `revived`, `closed`
- opened_at
- last_message_at
- dormant_at
- closed_at
- starter message id
- most recent message id
- participant summary
- entity summary
- open pending-item count
- topic summary
- confidence summary
- reconstruction version

#### Conversation membership contract
`ConversationMembership` should support both message membership and actor participation with:
- conversation id
- member kind:
  `message`, `actor`, `entity`, `pending_item`
- member id
- role:
  `starter`, `participant`, `mentioned`, `resolver`, `observer`
- score
- join reason
- supporting evidence array
- attached_at
- detached_at when later reassigned

#### Pending item contract
`PendingItem` should represent unresolved conversational state with:
- conversation id
- opener message id
- resolver message id when closed
- item kind:
  `question`, `request`, `task`, `issue`, `decision`
- status:
  `open`, `answered`, `completed`, `expired`, `abandoned`
- owner actor ids when inferred
- referenced entity ids
- opened_at
- resolved_at
- summary text
- confidence
- supporting evidence array

Messages may remain unattached to any conversation or pending item when no candidate exceeds the configured threshold. That behavior is intentional and should be preserved in the contract.

### Key stored message attributes
- platform, workspace or guild, and channel
- external message identifiers and platform thread or reply identifiers when available
- timestamp and actor identity at observation time
- raw body, normalized body, mentions, quoted references, attachments, links, reactions, and metadata
- embedding, dialogue act, extracted entities, topics, and other enrichment outputs

### Online inference flow
For each new message:
1. Normalize actor identity and record alias observations.
2. Parse explicit mentions, reply metadata, quotes, and platform thread identifiers.
3. Compute embeddings and lightweight enrichment such as dialogue act and entities.
4. Retrieve candidate parent messages from a bounded recent window plus relevant unresolved items and recent conversations.
5. Score candidate message links and candidate conversations using explicit reply signals, actor overlap, dialogue-act compatibility, entity overlap, semantic similarity, turn-taking, and time decay.
6. Attach the message to the best supported conversation, revive a dormant one, or start a new conversation if no candidate is strong enough.
7. Persist confidence scores and contributing evidence for every inferred edge.

### Batch enrichment flow
- summarize conversation segments
- resolve ambiguous low-margin links
- merge or split suspicious local clusters
- update relationship weights and temporal decay
- generate conversation-level embeddings and topic summaries

## Scoring Approach
The first pass should use a weighted scoring model rather than a fully learned end-to-end classifier. Candidate features include:
- explicit reply or thread metadata
- direct addressing or mention of the prior speaker
- question-to-answer or request-to-acknowledgment dialogue-act match
- semantic similarity between message and candidate context
- overlap in extracted entities, topics, links, hosts, or other rare artifacts
- participant continuity and turn-taking patterns
- time decay and penalties for topic shifts or stronger competing parents

Low-confidence messages may remain unattached or only weakly linked. That is preferable to fabricating threads.

## Query and Graph Implications
Analyst questions such as "what did alice talk about with bob last week?" should retrieve conversation objects in the requested time range, rank them by direct interaction evidence, and summarize the topics, claims, tasks, and outcomes with message citations. Relationship edges such as `INTERACTED_WITH`, `ANSWERED`, or `COLLABORATED_WITH` should be derived from message and conversation evidence rather than mere co-presence in the same room.

## Risks / Trade-offs
- The system may still create false reply links in noisy channels.
  Mitigation: keep thresholds conservative, store evidence, and allow later reassignment.

- Identity resolution can overmerge unrelated IRC users.
  Mitigation: prefer conservative alias tracking and only elevate weak signals with operator review or stronger evidence.

- Additional per-message inference increases ingest cost.
  Mitigation: keep the hot path bounded, reserve expensive LLM work for batch arbitration, and reuse existing embeddings and extraction outputs.

- Long-lived conversations can drift or fork.
  Mitigation: support split and merge operations and keep conversation state centered on entities, participants, and unresolved items instead of a single ever-growing thread.

## Migration Plan
1. Define the canonical event, alias, conversation, and evidence contracts.
2. Persist enough metadata from IRC and Discord ingest to replay conversation reconstruction.
3. Add online candidate retrieval and scoring for message links and conversation assignment.
4. Add dormant conversation revival and pending-item resolution.
5. Add batch summarization, relationship weighting, and analyst retrieval over conversations.

## Open Questions
- Should the canonical event store live entirely in the Elixir tenant schema, or should some high-volume event projections remain in Neo4j-first paths while Elixir owns only reconstructed state?
- Which dialogue-act label set is the smallest useful first pass for this project: question, answer, request, acknowledgment, agreement, disagreement, status update, and observation, or something broader?
