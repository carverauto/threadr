## ADDED Requirements
### Requirement: Tenant QA uses shared hybrid retrieval primitives
Threadr 2.0 SHALL answer tenant QA questions through a shared hybrid retrieval layer that can combine lexical, vector, and actor or time or channel constrained evidence instead of relying on a single retrieval mode at a time.

#### Scenario: Single-actor topical questions use actor-constrained hybrid retrieval
- **WHEN** a user asks a question about what a known actor talked about during a bounded period
- **THEN** Threadr retrieves evidence from that actor's message history using actor constraints plus lexical or vector candidate generation
- **AND** Threadr does not require the user's rhetorical framing words to appear verbatim in the actor's messages
- **AND** the returned evidence can span the requested period instead of only the most recent few messages

#### Scenario: Exact-term and slang questions use lexical evidence
- **WHEN** a user asks who mentioned a term, slang phrase, nickname, or short lexical expression
- **THEN** Threadr includes lexical retrieval in the candidate set
- **AND** fuzzy lexical retrieval uses PostgreSQL `pg_trgm` over tenant message history
- **AND** Threadr can retrieve relevant messages even when vector similarity alone is weak

### Requirement: Time-bounded recaps use broader message-window retrieval
Threadr 2.0 SHALL answer recap and summary questions from a bounded tenant message window for the requested scope instead of relying only on reconstructed conversations.

#### Scenario: Current-channel recap spans the requested day
- **WHEN** a user asks for the topics or discussions from today in a specific channel
- **THEN** Threadr retrieves a bounded message window covering that day and channel
- **AND** Threadr may combine reconstructed conversation evidence with raw message-window evidence
- **AND** the answer is not limited to only the latest recent reconstructed cluster

### Requirement: Graph-answer retrieval uses the same hybrid evidence base
Threadr 2.0 SHALL seed graph-answer retrieval from the same hybrid message candidate set used by normal tenant QA before expanding graph neighborhood context.

#### Scenario: Graph answer and standard QA agree on core evidence
- **WHEN** a user asks the same tenant question through the standard QA surface and the graph-answer surface
- **THEN** both surfaces begin from materially similar relevant message evidence
- **AND** the graph-answer surface adds graph neighborhood context on top of that evidence instead of replacing it with unrelated semantic hits

## MODIFIED Requirements
### Requirement: Bot and UI QA resolve actor-focused questions through actor-centric retrieval
Threadr 2.0 SHALL resolve actor-focused bot and UI questions through actor-aware retrieval that uses shared hybrid search primitives before falling back to generic GraphRAG or semantic QA.

#### Scenario: Bot user asks what a known actor talks about
- **WHEN** a user asks a deployed bot what a known tenant actor mostly talks about
- **THEN** Threadr resolves the referenced handle to a tenant actor record
- **AND** retrieves grounded actor-specific evidence from hybrid lexical, vector, and constrained search over that actor's tenant history
- **AND** returns an actor-specific answer instead of only reporting missing generic context

#### Scenario: UI user asks what one actor says about another actor
- **WHEN** a tenant user asks the web QA interface what actor A says about actor B
- **THEN** Threadr resolves the referenced actor handles in the tenant scope
- **AND** retrieves grounded actor-specific evidence before generic semantic fallback
- **AND** returns an answer with the same actor-centric grounding behavior used for bot QA
