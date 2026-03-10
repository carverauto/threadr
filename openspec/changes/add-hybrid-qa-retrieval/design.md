## Context
Threadr currently has several retrieval paths:
- vector search through `SemanticQA`
- actor or time constrained message filters through `ConstrainedQA`
- reconstructed conversation retrieval through `ConversationQA` and `ConversationSummaryQA`
- graph expansion seeded from semantic results through `GraphRAG`

These paths solve different problems, but they do not share a common candidate-generation and reranking layer. As a result:
- single-actor questions often retrieve too shallow a slice
- slang, nicknames, insults, and rhetorical wording are brittle when embeddings do not line up
- graph-answer and normal QA can see materially different evidence for the same question
- recap-style questions can miss large portions of a day if reconstruction coverage is incomplete

## Goals / Non-Goals
- Goals:
  - improve recall for tenant QA without adding more phrase-specific routers
  - make lexical and vector retrieval first-class and composable
  - share retrieval behavior across QA, graph-answer, and summary flows
  - preserve LLM answering while making retrieval less brittle and more explainable
- Non-Goals:
  - replace the LLM answer layer with a local NLP or intent-classification stack
  - remove reconstructed conversations as an evidence source
  - build a generic external search service outside PostgreSQL for this change

## Decisions
- Decision: Introduce a shared hybrid retriever instead of continuing to embed retrieval logic inside each QA module.
  - Reason: the current failure mode is duplicated, inconsistent candidate generation, not missing answer-generation logic.

- Decision: Add PostgreSQL lexical and fuzzy retrieval primitives alongside embeddings, using `pg_trgm` as the first fuzzy matching primitive.
  - Reason: slang, exact terms, nicknames, and misspellings are common in IRC and Discord and are poorly served by vector-only retrieval.

- Decision: Expand matched messages into bounded local windows before answer generation.
  - Reason: many questions are really about short runs of adjacent messages, not isolated hits.

- Decision: Use reranking over merged candidates rather than hard-gating on exact question shapes.
  - Reason: soft ranking is less brittle than adding more explicit question branches for every English phrasing variant.

## Retrieval Shape
The hybrid retriever should be able to combine:
- lexical term hits
- fuzzy term hits from `pg_trgm`
- vector similarity hits
- actor-filtered hits
- channel-filtered hits
- time-bounded hits
- reconstructed conversation-backed citations when relevant

The merged candidate set should then be reranked using a bounded scoring model that can consider:
- actor match
- channel match
- time-window match
- lexical overlap
- vector similarity
- recency
- reply adjacency or nearby-window support

## Risks / Trade-offs
- Broader retrieval windows can increase noise.
  - Mitigation: keep reranking bounded and expose retrieval metadata in result payloads.

- PostgreSQL lexical search can drift from the embedding-backed retrieval experience.
  - Mitigation: merge and rerank both sources rather than replacing one with the other.

- Adding indexes or derived search columns changes tenant-schema behavior.
  - Mitigation: keep the data model additive and validate tenant migration behavior before rollout.

## Migration Plan
1. Enable `pg_trgm` in the database and add additive tenant-schema trigram indexes or derived columns needed for lexical retrieval.
2. Introduce the shared hybrid retriever behind existing QA module boundaries.
3. Migrate `SemanticQA`, `ConstrainedQA`, `GraphRAG`, and `ConversationSummaryQA` one by one to use the shared retriever.
4. Keep existing request and answer shapes stable while adding retrieval metadata fields.

## Open Questions
- Should ParadeDB complement `pg_trgm` later, or is `pg_trgm` sufficient for the first slice?
- Which reranking features should be implemented heuristically first, and which should remain candidates for later model-based reranking?
