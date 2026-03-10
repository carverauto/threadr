## 1. Design and Schema
- [x] 1.1 Define the shared hybrid retrieval contract for lexical, vector, and constrained message retrieval.
- [x] 1.2 Enable the `pg_trgm` extension at the database level and add tenant message trigram indexes for fuzzy lexical retrieval.
- [x] 1.3 Define how message-window expansion and reranking combine with existing reconstructed conversation evidence.

## 2. Retrieval Implementation
- [x] 2.1 Implement a shared hybrid retriever module for tenant message QA.
- [x] 2.2 Implement lexical retrieval over tenant messages with exact-term and `pg_trgm`-backed fuzzy matching support.
- [x] 2.3 Implement retrieval merging and reranking across lexical, vector, and actor or time or channel constrained candidates.
- [x] 2.4 Implement message-window expansion around matched messages and reply-adjacent context.

## 3. QA Integration
- [x] 3.1 Update semantic QA to use the shared hybrid retriever instead of vector-only retrieval.
- [x] 3.2 Update constrained QA to use the shared hybrid retriever for actor and topical questions without adding new phrase-specific routing.
- [x] 3.3 Update graph-answer retrieval to seed graph context from the shared hybrid retriever before graph expansion.
- [x] 3.4 Update time-bounded summary and recap retrieval to use the shared hybrid retriever over the requested message window.

## 4. Verification
- [x] 4.1 Add coverage for slang, nicknames, rhetorical wording, and actor-topic questions that should retrieve older same-day evidence.
- [x] 4.2 Add coverage for channel recap questions that must span the requested day rather than only the latest recent cluster.
- [x] 4.3 Verify bot, UI answer, and graph-answer surfaces return materially similar evidence for equivalent questions.
