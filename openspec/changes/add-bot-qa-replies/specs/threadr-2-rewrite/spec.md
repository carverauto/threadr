## ADDED Requirements
### Requirement: Deployed bots answer direct addressed questions in-channel
Threadr 2.0 SHALL allow deployed IRC and Discord bots to answer tenant-scoped questions when a user directly addresses the bot in a supported channel.

#### Scenario: IRC user asks the bot a direct question
- **WHEN** an IRC user sends a channel message that directly addresses the configured bot nickname with a tenant question
- **THEN** Threadr detects the addressed question
- **AND** runs the question against the tenant-scoped answer pipeline
- **AND** publishes a reply back into the same IRC channel

#### Scenario: Discord user asks the bot a direct question
- **WHEN** a Discord user sends a message that directly mentions the deployed bot with a tenant question
- **THEN** Threadr detects the addressed question
- **AND** runs the question against the tenant-scoped answer pipeline
- **AND** publishes a reply back into the same Discord channel

### Requirement: Bot replies are grounded and explicit about failure states
Threadr 2.0 SHALL return grounded replies for direct bot questions and SHALL surface explicit fallback responses when the system cannot answer.

#### Scenario: Context is insufficient for a grounded answer
- **WHEN** a directly addressed question does not have enough tenant context to answer safely
- **THEN** the bot replies that the available tenant context is insufficient
- **AND** the bot does not fabricate unsupported details

#### Scenario: Reply generation or publishing fails
- **WHEN** Threadr cannot generate an answer or cannot publish the reply to the source platform
- **THEN** the system records structured failure metadata for the bot question
- **AND** operators can inspect the failure without requiring raw platform logs alone
