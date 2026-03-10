# Change: Add hybrid QA retrieval and search primitives

## Why
Threadr's current QA retrieval is too brittle and too shallow. Single-actor questions, recap questions, slang or nickname-heavy prompts, and graph-answer flows often miss obviously relevant tenant history because the system over-relies on one retrieval mode at a time: vector search, reconstructed conversations, or small filtered message slices.

The result is poor recall, inconsistent answers across UI and bot surfaces, and too much pressure to keep adding ad hoc question-shape routing. The system needs better shared retrieval primitives instead of more phrase handlers.

## What Changes
- Add a shared hybrid retrieval layer that can combine lexical, vector, and actor or time or channel constrained retrieval.
- Add PostgreSQL-backed lexical search primitives for tenant messages, using exact-term retrieval plus fuzzy matching through `pg_trgm`.
- Add message-window expansion and reranking so answers are grounded in surrounding conversational context rather than isolated hits.
- Update QA, graph-answer, and time-bounded summary flows to use the shared retrieval layer instead of bespoke per-module retrieval logic.
- Expose retrieval metadata that shows which evidence sources contributed to an answer.

## Impact
- Affected specs: `threadr-2-rewrite`
- Affected code: `Threadr.ML.SemanticQA`, `Threadr.ML.ConstrainedQA`, `Threadr.ML.GraphRAG`, `Threadr.ML.ConversationSummaryQA`, message search and indexing paths, and tenant QA or graph UI surfaces
