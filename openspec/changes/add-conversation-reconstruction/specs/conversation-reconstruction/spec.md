## ADDED Requirements
### Requirement: Threadr defines a canonical public-channel event contract for reconstruction
Threadr SHALL define a canonical tenant-scoped public-channel event contract that preserves immutable message events, append-only context events, and normalized reconstruction metadata across supported chat platforms.

#### Scenario: A message edit arrives after the original message was stored
- **WHEN** Threadr receives a later edit or delete for an existing public message
- **THEN** Threadr keeps the original message event immutable
- **AND** records an append-only context event that references the affected message
- **AND** exposes normalized metadata such as reply ids, thread ids, quoted references, and edit or delete timestamps to reconstruction logic

#### Scenario: IRC and Discord produce different raw payload shapes
- **WHEN** supported platforms provide different native fields for replies, threads, reactions, or presence changes
- **THEN** Threadr maps the fields into a shared normalized metadata contract for reconstruction
- **AND** retains the raw platform payload for replay and debugging without forcing reconstruction to depend on platform-specific keys

### Requirement: Threadr models aliases separately from canonical actors
Threadr SHALL model canonical actors, aliases, and alias observations as separate records and use conservative rules before changing canonical actor ownership.

#### Scenario: An IRC nick changes in the middle of an active channel discussion
- **WHEN** a user changes nick after previously posting in the same tenant
- **THEN** Threadr records a new alias observation and any explicit nick-change context event
- **AND** may associate the alias with an existing actor only when continuity evidence supports it
- **AND** does not silently rewrite historical message authorship from weak similarity alone

#### Scenario: A platform provides a stable account id and a mutable display name
- **WHEN** Discord or another platform emits the same account id with a changed display name or handle
- **THEN** Threadr can attach the new alias observation to the existing canonical actor
- **AND** preserves the alias history as separate observed values instead of collapsing it into one mutable string

### Requirement: Threadr stores reconstruction links and conversation state as evidence-bearing records
Threadr SHALL persist message links, conversation objects, conversation memberships, and pending items as scored records with explicit evidence and versioned inference metadata.

#### Scenario: A reply candidate wins by only a narrow evidence margin
- **WHEN** Threadr links a message to a candidate parent or conversation with limited separation from competing candidates
- **THEN** the stored record includes the winning score, candidate margin, evidence details, and inference version
- **AND** later batch jobs can re-evaluate or detach the link without losing provenance

#### Scenario: A message does not confidently belong to any conversation
- **WHEN** no candidate conversation or parent message exceeds the configured attachment threshold
- **THEN** Threadr may leave the message unattached or weakly linked
- **AND** the contract does not require every message to belong to exactly one conversation

### Requirement: Threadr stores complete public-channel event history for reconstruction
Threadr SHALL persist every observed public-channel message and relevant context event needed to reconstruct conversations, identity continuity, and downstream graph evidence.

#### Scenario: IRC nick change is preserved as context instead of overwriting identity
- **WHEN** an IRC user changes nick after posting in a monitored channel
- **THEN** Threadr keeps the original messages unchanged
- **AND** records the nick-change event and alias observation with timestamps
- **AND** does not rewrite prior message authorship to a different canonical actor without separate identity evidence

#### Scenario: Discord reply metadata is captured for later reconstruction
- **WHEN** a Discord message includes platform reply or thread metadata
- **THEN** Threadr stores that metadata alongside the normalized message event
- **AND** makes it available to conversation-link inference and analyst retrieval

### Requirement: Threadr infers conversation links with multi-signal scoring
Threadr SHALL infer message-to-message and message-to-conversation links from multiple signals, including but not limited to explicit replies, direct addressing, dialogue-act compatibility, entity overlap, semantic similarity, turn-taking, and time decay.

#### Scenario: A directly addressed exchange continues without repeated mentions
- **WHEN** Alice asks `bob: did the backup finish on server xyz?` and Bob continues the exchange in following messages without another direct mention
- **THEN** Threadr can keep the later messages in the same reconstructed conversation
- **AND** the inferred links are supported by scored evidence beyond the initial nickname prefix alone

#### Scenario: Busy-channel ambiguity does not force a bad link
- **WHEN** a short reply such as `yeah` appears in a channel with multiple recent conversations and no strong distinguishing evidence
- **THEN** Threadr may leave the message unattached or weakly linked
- **AND** it does not require every message to have a single high-confidence parent

### Requirement: Threadr maintains active, dormant, and revived conversation state
Threadr SHALL maintain conversation objects that track participants, relevant entities, unresolved questions or tasks, and status transitions so long-running conversations can resume after gaps.

#### Scenario: A delayed answer revives a dormant conversation
- **WHEN** Alice asks Bob a question in a monitored channel and Bob answers days later without using a direct reply feature
- **THEN** Threadr can revive the earlier conversation if the later message strongly matches the unresolved question or task state
- **AND** creates evidence-backed links between the answer, the conversation, and the earlier message

#### Scenario: Parallel conversations remain disentangled
- **WHEN** several sub-conversations happen in the same channel during the same time window
- **THEN** Threadr scores message and conversation candidates using participant, entity, and dialogue-flow evidence
- **AND** keeps unrelated exchanges in separate reconstructed conversations when the evidence supports separation

### Requirement: Relationship and QA retrieval are grounded in reconstructed conversations
Threadr SHALL answer actor-to-actor conversation questions and derive actor relationship evidence from reconstructed conversations with supporting message references and confidence metadata.

#### Scenario: Analyst asks what Alice talked about with Bob last week
- **WHEN** an analyst requests `what did alice talk about with bob last week?`
- **THEN** Threadr retrieves conversations from the requested time range where Alice and Bob were direct or strongly inferred participants
- **AND** summarizes the topics, tasks, claims, or outcomes from those conversations
- **AND** includes supporting message references or other provenance for the answer

#### Scenario: Relationship strength reflects evidence type rather than room co-presence
- **WHEN** two actors share a channel but rarely exchange direct, inferred, or conversation-level interactions
- **THEN** Threadr does not inflate their relationship strength from co-presence alone
- **AND** favors evidence such as replies, answered questions, sustained exchanges, and repeated topic collaboration
