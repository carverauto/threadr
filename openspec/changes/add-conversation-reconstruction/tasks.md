## 1. Specification
- [x] 1.1 Define the canonical public-channel event schema, including message, reply, edit, delete, reaction, and presence-context metadata.
- [x] 1.2 Define the actor, alias, and alias-observation model plus conservative merge rules.
- [x] 1.3 Define the message-link, conversation, membership, and pending-item evidence contracts.

## 2. Ingest And Storage
- [x] 2.1 Update IRC ingest to emit all required message and context metadata for reconstruction.
- [x] 2.2 Update Discord ingest to emit all required message and context metadata for reconstruction.
- [x] 2.3 Persist canonical events and alias observations in tenant-scoped storage and projection paths.

## 3. Online Conversation Reconstruction
- [x] 3.1 Add dialogue-act classification and entity extraction outputs required for link scoring.
- [x] 3.2 Implement bounded candidate retrieval over recent messages, active conversations, and unresolved items.
- [x] 3.3 Implement confidence-scored message-link inference with evidence capture.
- [x] 3.4 Implement conversation attachment, dormancy, revival, and new-conversation creation rules.

## 4. Batch Enrichment
- [x] 4.1 Add periodic summarization and topic extraction for conversation objects.
- [x] 4.2 Add merge or split review for ambiguous local conversation clusters.
- [x] 4.3 Recompute actor relationship weights from message and conversation evidence with temporal decay.

## 5. Analyst Retrieval
- [x] 5.1 Retrieve actor-to-actor interaction history from reconstructed conversations, not raw adjacency alone.
- [x] 5.2 Add grounded summaries with supporting message references for time-bounded conversation questions.

## 6. Verification
- [x] 6.1 Add fixtures covering continued discussions without repeated mentions.
- [x] 6.2 Add fixtures covering delayed answers that revive dormant conversations.
- [x] 6.3 Add fixtures covering parallel conversations in one busy channel.
- [x] 6.4 Add fixtures covering IRC nick changes without unsafe identity merges.
- [x] 6.5 Add fixtures proving ambiguous low-confidence messages can remain unattached.
