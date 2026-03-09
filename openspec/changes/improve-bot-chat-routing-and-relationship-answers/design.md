## Context
The current bot QA flow treats nearly every direct-addressed turn as a retrieval problem. That works for some analyst-style questions, but it produces obviously bad behavior for ordinary chat. The same routing surface is also too narrow for actor relationship questions, which means the bot often answers `not enough context` even when reconstructed interaction evidence exists.

These failures are coupled:

- bot turns need an intent gate before retrieval
- relationship questions need a dedicated retrieval mode instead of hoping semantic fallback will cover them
- self-reference must be resolved from bot runtime context before relationship retrieval
- evidence rendering should preserve canonical channel names exactly as stored
- IRC actor visibility is too message-driven, so dossiers and relationship lookup miss obvious participants until they speak

## Goals
- Distinguish conversational bot turns from analyst-style retrieval questions.
- Answer actor interaction questions from grounded tenant evidence instead of generic fallback.
- Resolve `I`, `me`, and similar self references against the current bot requester when available.
- Remove duplicate channel-prefix rendering in bot-visible evidence.
- Hydrate IRC channel actor presence from roster information so known occupants are queryable before first message.

## Non-Goals
- General-purpose open-ended chat memory outside tenant context.
- A full natural-language intent taxonomy for every possible QA mode.
- Replacing reconstructed conversation QA with a pure relationship-table solution.

## Approach

### 1. Add a lightweight bot chat intent boundary
Introduce a dedicated bot intent step ahead of QA orchestration. Its job is not deep NLU; it only needs to separate:

- conversational chat such as greetings, acknowledgements, and general assistant turns
- analyst retrieval questions
- relationship questions that should use a specialized interaction path

Conversational turns should route to a chatbot-style generation path with bot identity and tenant context available as optional prompt context, but without retrieval citations being treated as required evidence.

### 2. Add actor relationship QA for `talks with` questions
Add a retrieval mode focused on interaction partners for questions such as:

- `who does sh4rp mostly talk with?`
- `who does sig talk with the most?`
- `who do I mostly talk with?`

This path should prefer reconstructed conversation and direct interaction evidence over raw co-presence. Suitable evidence sources include:

- shared reconstructed conversations
- reply or answer links
- conversation memberships and repeated turn-taking
- relationship recompute outputs where they reflect conversation-backed evidence

The answer contract should surface the strongest interaction partners plus supporting message or conversation references.

### 3. Resolve requester self-reference before relationship retrieval
Self-reference for bot turns should use the requester identity passed in from the runtime and should map to the corresponding tenant actor when possible. If resolution fails, the bot should say the requester could not be matched rather than silently falling back to irrelevant context.

### 4. Normalize channel labels at one rendering boundary
Introduce a shared channel-label formatter for bot-visible citations and summaries. It should preserve names that already start with `#` and only add a prefix when the underlying platform representation requires it.

### 5. Hydrate IRC actor presence from channel rosters
The IRC ingest runtime should stop learning actors only from emitted messages. When the bot joins a channel, it should request or consume the channel roster and emit a normalized context event that contains the visible nick list.

That roster event should be enough to:

- upsert actor rows for visible IRC nicks immediately
- preserve roster observations as tenant-scoped evidence
- support faster actor lookup in dossiers and bot QA even when the target actor has not spoken yet in the current retained history

The roster signal should stay evidence-bearing rather than silently rewriting identity. A channel roster is presence evidence, not proof that two nick strings belong to one canonical actor.

## Risks
- Overly broad conversational intent matching could steal real analyst questions from retrieval.
- Relationship answers could overcount co-presence if they do not stay grounded in reconstruction evidence.
- Self-reference resolution can be wrong when runtime requester identity is missing or mismatched.
- IRC roster snapshots can introduce noisy presence-only actors if roster handling is treated as stronger evidence than it really is.

## Mitigations
- Keep the conversational intent boundary intentionally narrow and test the fallthrough behavior.
- Prefer reconstructed-conversation evidence and reply links over simple same-channel counts.
- Treat requester self-reference as best-effort and fail explicitly when actor resolution is ambiguous.
- Persist roster membership as explicit presence evidence and keep relationship scoring separate from mere channel occupancy.
