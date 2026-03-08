# Change: Add Interactive Bot QA Replies

## Why
Threadr bots currently ingest IRC and Discord messages into the tenant history, but they do not respond in-channel when directly addressed. This leaves the deployed bot feeling broken from a user perspective because asking `threadr: what did alice and bob talk about last week?` produces no reply even though the system already has tenant QA and graph-RAG capabilities in the control plane.

## What Changes
- Add a bot-runtime mention and direct-address detection path for IRC and Discord.
- Route bot-addressed questions into the existing tenant QA and graph-RAG answer flow.
- Publish grounded replies back into the originating IRC channel or Discord channel.
- Add guardrails so bots only answer when directly addressed and can refuse when tenant context is insufficient or the request is unsupported.
- Record enough metadata to trace a bot question, generated answer, and reply outcome.

## Impact
- Affected specs: `threadr-2-rewrite`
- Affected code: bot runtimes, ingest pipeline, command routing, control-plane QA services, and reply-publishing adapters
