## 1. Bot Routing
- [x] 1.1 Add a dedicated bot intent boundary that distinguishes conversational turns from retrieval questions.
- [x] 1.2 Route normal direct-addressed chatbot turns through a non-retrieval conversational generation path.
- [x] 1.3 Preserve existing analyst-style QA fallback behavior for questions that do not match the conversational path.

## 2. Relationship QA
- [x] 2.1 Add a specialized actor relationship QA path for `talks with` and `talks with the most` questions.
- [x] 2.2 Ground relationship answers in reconstructed conversation and direct interaction evidence instead of raw co-presence alone.
- [x] 2.3 Support requester self-reference such as `who do I mostly talk with?` when bot runtime identity is available.

## 3. Reply Formatting
- [x] 3.1 Add a shared channel-label formatter for bot-visible evidence rendering.
- [x] 3.2 Stop double-prefixing channel names that already include `#`.

## 4. IRC Actor Hydration
- [x] 4.1 Consume IRC roster or `NAMES` replies after channel join.
- [x] 4.2 Persist roster-backed actor presence so visible nicks are queryable before first message.
- [x] 4.3 Preserve roster evidence separately from message authorship and relationship-strength inference.

## 5. Verification
- [x] 5.1 Add bot QA regressions for conversational turns like `threadr: hello`.
- [x] 5.2 Add regressions for actor relationship questions such as `who does sh4rp mostly talk with?`.
- [x] 5.3 Add regressions for requester self-reference such as `who do I mostly talk with?`.
- [x] 5.4 Add regressions proving IRC channel names render with a single `#`.
- [x] 5.5 Add IRC ingest regressions for roster hydration on join or `NAMES`.
