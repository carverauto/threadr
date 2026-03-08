## Context
Threadr already supports tenant-scoped semantic QA and graph-RAG in the Phoenix control plane, and deployed IRC bots now successfully ingest and normalize channel messages. What is missing is the runtime path that recognizes a user addressing the bot, transforms that message into a tenant question, invokes the existing answer pipeline, and sends a reply back to the same platform.

The change crosses multiple boundaries:
- IRC and Discord runtime parsing
- tenant-scoped answer generation
- platform-specific outbound reply publishing
- observability and failure handling

## Goals
- Let IRC and Discord users ask direct bot questions in-channel.
- Reuse the existing tenant QA and graph-RAG service layer instead of building a second answer stack.
- Keep replies grounded in tenant data and explicit about insufficient context.
- Make reply attempts observable for debugging and operator support.

## Non-Goals
- General conversational memory beyond the addressed question.
- Multi-turn session management.
- Slash-command or Discord interactions support.
- Private-message workflows in this first pass unless already required by the platform adapter.

## Decisions
- Decision: Trigger answers only when the bot is directly addressed.
  Reason: This avoids noisy accidental replies and keeps platform behavior predictable.

- Decision: Reuse existing control-plane QA and graph-RAG services as the answer engine.
  Reason: The repository already has tenant-aware retrieval and answer generation paths that should remain the single source of truth.

- Decision: Keep reply publishing in the bot runtime layer, not the control plane.
  Reason: Platform tokens and connection state already live with the runtime adapter, and the control plane should not become a chat-transport client.

- Decision: Persist or emit structured metadata for addressed questions and reply outcomes.
  Reason: Operators need a way to debug failed answer generation, reply failures, and user-visible delays.

## Risks / Trade-offs
- Calling QA flows synchronously from the bot runtime can introduce reply latency.
  Mitigation: start with a synchronous path for correctness, then optimize if needed.

- Platform-specific mention formats differ between IRC and Discord.
  Mitigation: define an explicit direct-address normalization contract per adapter.

- LLM-backed answers may fail or return low-confidence results.
  Mitigation: return a short refusal or insufficient-context reply rather than timing out silently.

## Migration Plan
1. Specify direct-address detection and reply behavior.
2. Implement a shared addressed-question pipeline inside the Elixir runtime.
3. Add IRC reply publishing, then Discord reply publishing.
4. Add tests and a smoke path for an end-to-end addressed question.

## Open Questions
- Should the first pass support only `threadr: ...` / `<@bot> ...`, or also plain nickname mentions inside longer messages?
- Should replies default to semantic QA, graph-RAG, or choose between them based on the question shape?
- Do we want a user-visible “thinking…” acknowledgment for slower answers?
