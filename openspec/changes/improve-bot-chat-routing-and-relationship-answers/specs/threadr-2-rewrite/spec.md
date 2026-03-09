## ADDED Requirements
### Requirement: Direct-addressed bot chat distinguishes conversational turns from retrieval questions
Threadr 2.0 SHALL route direct-addressed bot turns through a lightweight intent boundary so ordinary chatbot interaction does not always go through retrieval-first QA.

#### Scenario: User greets the bot in a channel
- **WHEN** a user addresses the bot with a normal conversational turn such as `threadr: hello`
- **THEN** Threadr responds as a conversational assistant instead of summarizing retrieved tenant messages
- **AND** the reply does not require analyst-style citations or context excerpts to be useful

#### Scenario: User asks an analyst-style question through the bot
- **WHEN** a user addresses the bot with a tenant-history question rather than casual chat
- **THEN** Threadr still routes the turn through the appropriate grounded retrieval path
- **AND** conversational routing does not suppress the analyst QA behavior

### Requirement: Actor interaction questions are answered from grounded interaction evidence
Threadr 2.0 SHALL answer `talks with` style actor questions from reconstructed interaction evidence instead of falling back to generic semantic QA or room co-presence alone.

#### Scenario: User asks who an actor mostly talks with
- **WHEN** a user asks `who does sh4rp mostly talk with?` or `who does sig talk with the most?`
- **THEN** Threadr resolves the referenced actor in tenant scope
- **AND** retrieves likely interaction partners from reconstructed conversations, reply evidence, or equivalent interaction records
- **AND** answers with grounded evidence instead of only saying the context is insufficient

#### Scenario: User asks who they mostly talk with
- **WHEN** a direct-addressed bot user asks `who do I mostly talk with?`
- **THEN** Threadr uses the requester runtime identity to resolve the speaking actor in tenant scope when possible
- **AND** answers from the same grounded interaction evidence used for named actors
- **AND** fails explicitly when the requester cannot be matched safely

### Requirement: Bot-visible evidence preserves canonical channel names
Threadr 2.0 SHALL preserve canonical channel names when rendering bot-visible citations and summaries.

#### Scenario: IRC channel names already include a leading hash
- **WHEN** Threadr renders bot-facing evidence for a stored IRC channel such as `#!chases`
- **THEN** the rendered channel label appears with a single leading `#`
- **AND** Threadr does not prepend an additional hash that would produce `##!chases`

### Requirement: IRC roster presence hydrates visible actors before first message
Threadr 2.0 SHALL use IRC channel roster information to hydrate visible actors as evidence-bearing tenant records before they speak.

#### Scenario: Bot joins an IRC channel and receives the visible nick list
- **WHEN** the IRC runtime joins a monitored channel and receives the roster or `NAMES` reply
- **THEN** Threadr records a normalized roster-style context event or equivalent evidence
- **AND** upserts actor records for the visible nicks in tenant scope
- **AND** preserves the roster observation as presence evidence instead of pretending each actor has already spoken

#### Scenario: Analyst inspects a dossier for a message directed at a silent channel occupant
- **WHEN** a dossier or QA flow needs to resolve an IRC nick that has been seen in channel roster evidence but has not yet authored a retained message
- **THEN** Threadr can still resolve the nick to a tenant actor candidate
- **AND** the system distinguishes roster presence from message authorship and stronger interaction evidence
