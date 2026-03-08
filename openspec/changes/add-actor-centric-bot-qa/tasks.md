## 1. QA Retrieval
- [x] 1.1 Add actor-handle resolution for bot and UI QA questions before generic GraphRAG fallback.
- [x] 1.2 Add an actor-centric retrieval path for questions about what an actor talks about, knows, or says about another actor.
- [x] 1.3 Preserve grounded fallbacks for actor-not-found, ambiguous-actor, and insufficient-evidence cases.

## 2. Data Coverage
- [x] 2.1 Ensure retained tenant messages are embedding-complete or have a bounded catch-up path.
- [ ] 2.2 Add operational verification that message embeddings keep pace with ingested history for QA workloads.

## 3. Verification
- [x] 3.1 Verify bot QA can answer actor-centric questions for known actors in IRC or Discord tenants.
- [x] 3.2 Verify sparse actors still return explicit insufficient-evidence responses instead of fabricated summaries.
- [ ] 3.3 Verify UI QA uses the same actor-centric retrieval path as bot QA for equivalent questions.
