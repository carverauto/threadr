# Change: Improve Bot Chat Routing And Relationship Answers

## Why
The current direct-addressed bot experience is failing at basic interaction quality. Normal conversational turns like `threadr: hello` are routed through retrieval and answered with awkward context-grounded summaries instead of behaving like an LLM chatbot.

Actor relationship questions are also too weak to be useful. Questions such as `who does sh4rp mostly talk with?`, `who does sig talk with the most?`, and `who do I mostly talk with?` regularly fall through to generic fallback or produce incorrect answers even when tenant history contains relevant interaction evidence. In the same path, rendered channel names are sometimes prefixed as `##channel` because reply formatting assumes the stored name never already includes `#`.

## What Changes
- Add a dedicated bot conversation route for normal direct-addressed chat that does not force retrieval-first answering.
- Add a grounded actor relationship QA path for `talks with` and `talks with the most` style questions using reconstructed conversation and interaction evidence.
- Tighten requester self-reference handling for bot relationship questions such as `who do I mostly talk with?`.
- Normalize bot-facing channel rendering so stored channel names are preserved without adding duplicate `#` prefixes.
- Add IRC roster hydration on join or `NAMES` so visible channel actors exist in tenant state before they speak.

## Impact
- Affected specs: `threadr-2-rewrite`
- Affected code: bot QA routing, QA orchestration, actor or conversation retrieval, requester identity resolution, and message citation formatting
