package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/carverauto/threadr/pkg/api/nats"
)

const configKey = "natsConfiguration"

func main() {
	var (
		initFlag      = flag.Bool("init", false, "Initialize the NATS configuration.")
		newAccount    = flag.String("new-account", "", "Create a new account with the specified name.")
		newUser       = flag.String("new-user", "", "Create a new user with the specified name.")
		targetAccount = flag.String("target-account", "root", "Target account name for creating users or listing users.")
		listAccounts  = flag.Bool("list-accounts", false, "List all accounts.")
		listUsers     = flag.Bool("list-users", false, "List all users under the specified account.")
	)
	flag.Parse()

	if *initFlag {
		if err := handleInit(); err != nil {
			fmt.Printf("Initialization error: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("Setup complete. Configuration is now saved.")
		return
	}

	cfg, err := nats.LoadConfig(configKey)
	if err != nil {
		fmt.Printf("Failed to load configuration: %v\n", err)
		os.Exit(1)
	}

	if *newAccount != "" {
		jwt, updatedCfg, err := nats.AddTenant(*newAccount, cfg)
		if err != nil {
			fmt.Printf("Failed to create new account: %v\n", err)
			os.Exit(1)
		} else {
			cfg = updatedCfg // Update cfg with the changes
			fmt.Printf("New account created successfully. JWT: %s\n", jwt)
		}
	}

	if *newUser != "" && *targetAccount != "" {
		jwt, updatedCfg, err := nats.AddUserToTenant(*newUser, *targetAccount, cfg)
		if err != nil {
			fmt.Printf("Failed to create new user: %v\n", err)
			os.Exit(1)
		} else {
			cfg = updatedCfg // Update cfg with the changes
			fmt.Printf("New user created successfully. JWT: %s\n", jwt)
		}
	}

	if *listAccounts {
		handleListAccounts(cfg)
	}

	if *listUsers && *targetAccount != "" {
		handleListUsers(cfg, *targetAccount)
	}
}

func handleInit() error {
	cfg, err := nats.InitialSetup()
	if err != nil {
		return err
	}
	return nats.SaveConfig(cfg)
}

func handleListAccounts(cfg *nats.Config) {
	fmt.Println("Accounts:")
	for name := range cfg.Accounts {
		fmt.Println("- ", name)
	}
}

func handleListUsers(cfg *nats.Config, accountName string) {
	if account, exists := cfg.Accounts[accountName]; exists {
		fmt.Printf("Users in account '%s':\n", accountName)
		for userName, userJWT := range account.Users {
			fmt.Printf("- %s: %s\n", userName, userJWT)
		}
	} else {
		fmt.Printf("Account '%s' not found\n", accountName)
	}
}
