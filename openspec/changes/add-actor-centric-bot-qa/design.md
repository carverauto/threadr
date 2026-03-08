## Context
The current deployed bot QA flow answers direct-addressed questions, but it primarily relies on generic GraphRAG or semantic QA retrieval over message embeddings. In practice, actor-focused questions such as "what does twatbot talk about?" need a different retrieval path:
- resolve the referenced handle to a tenant actor record
- retrieve that actor's own messages and related evidence directly
- summarize from grounded actor-specific evidence

Live behavior showed two gaps:
- actor-focused questions return "provided context does not contain..." even when the actor exists
- tenant embedding coverage can lag behind ingested message volume, which reduces recall

## Goals / Non-Goals
- Goals:
  - Answer actor-centric questions through explicit actor lookup and actor-scoped retrieval.
  - Distinguish "actor not found", "actor found but insufficient evidence", and "answer available".
  - Ensure retained tenant messages are embedding-complete enough for QA retrieval paths.
- Non-Goals:
  - Building full conversation reconstruction in this change.
  - Adding sentiment classification or stylistic abuse labeling.
  - Replacing grounded fallback behavior with unconstrained generation.

## Decisions
- Decision: Add an actor-centric QA branch ahead of generic GraphRAG and semantic QA.
  - Reason: Questions about what one actor talks about are better served by direct actor evidence than by open-ended vector retrieval.

- Decision: Treat actor-handle resolution as a first-class QA step.
  - Reason: Bot users ask with IRC/Discord handles, not internal actor IDs.

- Decision: Require embedding completeness for retained tenant messages as an operational invariant.
  - Reason: Partial embedding coverage silently degrades QA quality and makes actor-centric fallbacks inconsistent.

## Risks / Trade-offs
- Risk: Loose handle matching could resolve to the wrong actor.
  - Mitigation: prefer exact handle matches, preserve platform scope, and fail safely on ambiguity.

- Risk: Actor summaries over very small message counts can overstate certainty.
  - Mitigation: require explicit insufficient-evidence responses for sparse actor histories.

- Risk: Full embedding coverage can add ingest or backfill cost.
  - Mitigation: permit asynchronous catch-up, but require bounded lag and a recoverable backfill path.

## Migration Plan
1. Add actor-handle resolution and actor-centric answer orchestration.
2. Add actor-focused answer formatting and fallback rules.
3. Ensure ingestion or backfill keeps embeddings current for retained tenant messages.
4. Verify direct bot and UI QA questions about known actors return grounded actor-specific answers.

## Open Questions
- Should actor-centric retrieval also include direct mentions of the actor by other users, or only the actor's own messages, in the first pass?
- Should the UI expose ambiguity when multiple actors share similar handles, or should the bot simply ask a clarifying follow-up?
