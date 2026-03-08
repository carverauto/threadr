## ADDED Requirements
### Requirement: Bot and UI QA resolve actor-focused questions through actor-centric retrieval
Threadr 2.0 SHALL resolve actor-focused bot and UI questions through an actor-centric retrieval path before falling back to generic GraphRAG or semantic QA.

#### Scenario: Bot user asks what a known actor talks about
- **WHEN** a user asks a deployed bot what a known tenant actor mostly talks about
- **THEN** Threadr resolves the referenced handle to a tenant actor record
- **AND** retrieves grounded evidence from that actor's tenant history
- **AND** returns an actor-specific answer instead of only reporting missing generic context

#### Scenario: UI user asks what one actor says about another actor
- **WHEN** a tenant user asks the web QA interface what actor A says about actor B
- **THEN** Threadr resolves the referenced actor handles in the tenant scope
- **AND** retrieves grounded actor-specific evidence before generic semantic fallback
- **AND** returns an answer with the same actor-centric grounding behavior used for bot QA

### Requirement: Actor-centric QA distinguishes missing actors from sparse evidence
Threadr 2.0 SHALL distinguish between actor resolution failure and insufficient evidence when answering actor-focused questions.

#### Scenario: Referenced actor is not present in tenant history
- **WHEN** a user asks about an actor handle that does not resolve to a tenant actor
- **THEN** Threadr replies that the actor is not present in the available tenant history
- **AND** Threadr does not imply that evidence was found but insufficient

#### Scenario: Referenced actor exists but evidence is too sparse
- **WHEN** a user asks about an actor who exists in tenant history but has too little grounded evidence for a safe summary
- **THEN** Threadr replies that the actor does not have enough grounded history for a reliable answer
- **AND** Threadr does not fabricate a topical summary

### Requirement: Tenant QA retrieval maintains embedding coverage for retained message history
Threadr 2.0 SHALL maintain embedding coverage for retained tenant message history used by QA retrieval.

#### Scenario: Tenant history grows through normal ingestion
- **WHEN** new tenant messages are retained for QA
- **THEN** Threadr produces embeddings for those retained messages or schedules bounded catch-up processing
- **AND** actor-centric and semantic retrieval paths can query current tenant history without relying on partial manual backfill

#### Scenario: Operators inspect QA readiness after backlog or restart
- **WHEN** operators inspect a tenant after ingest backlog, restart, or recovery
- **THEN** Threadr exposes whether retained tenant message history is fully embedded or still catching up
- **AND** QA failure states can distinguish missing embeddings from missing actor evidence
