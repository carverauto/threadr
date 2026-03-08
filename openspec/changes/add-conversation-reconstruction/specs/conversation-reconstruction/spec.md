## ADDED Requirements
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
