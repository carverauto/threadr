# Change: Add actor-centric bot QA retrieval

## Why
Direct bot questions like "what does larsin10 talk about?" are currently routed through generic GraphRAG or semantic QA retrieval. That path is too weak for actor-focused questions, especially when the actor has sparse history or only part of the tenant message history has embeddings.

## What Changes
- Add an actor-centric retrieval path for bot and UI QA questions that resolve referenced handles before generic semantic retrieval.
- Require actor-summary style answers for questions about what a specific actor talks about, knows, or says about another actor.
- Require complete tenant message embedding coverage for retained chat history instead of relying on partial embedding backfill.
- Keep grounded failure behavior when the named actor is missing or evidence is too sparse.

## Impact
- Affected specs: `threadr-2-rewrite`
- Affected code: bot QA entrypoints, tenant QA answer pipeline, actor lookup, embedding generation/backfill flows, control-plane QA services
