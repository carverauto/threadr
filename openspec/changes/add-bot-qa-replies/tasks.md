## 1. Specification
- [x] 1.1 Confirm the direct-address trigger contract for IRC and Discord.
- [x] 1.2 Confirm the first-pass answer path and reply format.

## 2. Runtime Routing
- [x] 2.1 Detect bot-addressed questions in the IRC runtime.
- [x] 2.2 Detect bot-addressed questions in the Discord runtime.
- [x] 2.3 Normalize addressed questions into a shared bot-QA request flow.

## 3. Answer Generation
- [x] 3.1 Add a tenant-scoped service entrypoint for bot-originated questions.
- [x] 3.2 Reuse existing QA or graph-RAG retrieval and answer generation.
- [x] 3.3 Return explicit insufficient-context or failure replies instead of silent drops.

## 4. Reply Publishing
- [x] 4.1 Publish IRC replies into the originating channel.
- [x] 4.2 Publish Discord replies into the originating channel.
- [x] 4.3 Record reply outcome metadata for observability and debugging.

## 5. Verification
- [x] 5.1 Add focused runtime tests for direct-address detection.
- [x] 5.2 Add tests for bot-originated tenant QA answer generation.
- [x] 5.3 Add an end-to-end smoke path proving an addressed question receives a reply.
