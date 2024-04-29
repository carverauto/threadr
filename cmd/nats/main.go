package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/carverauto/threadr/pkg/api/nats"
)

func main() {
	var (
		initFlag       = flag.Bool("init", false, "Initialize the NATS configuration.")
		forceFlag      = flag.Bool("force", false, "Force overwrite of existing configuration.")
		createAccFlag  = flag.Bool("new-account", false, "Create a new account JWT.")
		createUserFlag = flag.String("new-user", "", "Create a new user JWT.")
	)
	flag.Parse()

	configPath := filepath.Join(os.Getenv("HOME"), ".threadr", "config.json")
	configDir := filepath.Dir(configPath)

	if *initFlag {
		if err := os.MkdirAll(configDir, 0755); err != nil {
			fmt.Printf("Failed to create configuration directory: %v\n", err)
			os.Exit(1)
		}
		if _, err := os.Stat(configPath); err == nil && !*forceFlag {
			fmt.Println("Configuration already exists. Use -force to overwrite.")
			os.Exit(1)
		}
		fmt.Println("Initializing the NATS configuration...")
		if err := nats.InitialSetup(configPath); err != nil {
			fmt.Printf("Failed to complete initial setup: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("Setup complete. Configuration saved to:", configPath)
		return
	}

	cfg, err := nats.LoadConfig(configPath)
	if err != nil {
		fmt.Printf("Failed to load configuration: %v\n", err)
		os.Exit(1)
	}

	if *createAccFlag {
		fmt.Println("Creating a new account...")
		jwt, err := nats.CreateAccount(cfg.OperatorSeed, "NewAccount") // Uses the operator seed from config
		if err != nil {
			fmt.Printf("Failed to create new account: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("New account created successfully. JWT:", jwt)
	} else if *createUserFlag != "" {
		fmt.Printf("Creating a new user for account: %s...\n", *createUserFlag)
		jwt, err := nats.CreateUser(cfg.AccountSeed, "NewUser") // Uses the account seed from config
		if err != nil {
			fmt.Printf("Failed to create new user: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("New user created successfully. JWT:", jwt)
	} else {
		fmt.Println("No operation specified. Use -h for help.")
	}
}
