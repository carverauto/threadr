# NATS Configuration Management Tool

This tool provides a command-line interface to manage NATS configuration, including accounts and users within those accounts. It leverages the NATS library for creating JWTs and managing NATS-specific entities.
The tool is necessary to boot-strap the NATS configuration before running the NATS server. It is also useful for managing accounts and users after the server is running.

Cloud users do not need to use this tool as the configuration is managed by the cloud service.

## Installation

Clone the repository and build the project:

```bash
git clone https://github.com/carverauto/threadr.git
cd threadr
go build .
```

## Usage
The tool supports several commands and options to initialize the configuration, create new accounts, add users, and list accounts or users.

### Commands

```
--init: Initialize the NATS configuration.
--new-account: Create a new account with the specified name.
--new-user: Create a new user with the specified name.
--target-account: Specify the target account name for creating users or listing users. Defaults to 'root' if not specified.
--list-accounts: List all accounts.
--list-users: List all users under the specified account.
```

### Examples

Initializing the Configuration

Initializes the NATS configuration. This is typically done once before other operations.

```bash
./threadr --init
```

### Creating an Account

Creates a new account named 'example'.

```bash
./threadr --new-account example
```

### Adding a User

Adds a new user named 'alice' to the 'example' account.

```bash
./threadr --new-user alice --target-account example
```

If no target account is specified, it defaults to the 'root' account.

```bash
./threadr --new-user alice
```

### Listing Accounts

Displays all accounts managed by the configuration.

```bash
./threadr --list-accounts
```

### Listing Users in an Account

Lists all users within the 'example' account.

```bash
./threadr --list-users --target-account example
```

### Configurations

This tool uses charm to manage the configuration. Install the [charm cli](https://github.com/charmbracelet/charm) to do more advanced operations on the KV.

```bash
# macos or linux
brew install charmbracelet/tap/charm
```

```bash
**Notes**

Ensure that you have the appropriate permissions when interacting with the configuration file and executing commands that modify the NATS configuration.