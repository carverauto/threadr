package cmd

import (
	"os"

	"github.com/carverauto/threadr/pkg/api/nats"
	"github.com/spf13/cobra"
)

var addAccountCmd = &cobra.Command{
	Use:   "add-account [name]",
	Short: "Create a new account with the specified name",
	Args:  cobra.ExactArgs(1), // Ensure exactly one argument is passed
	Run: func(cmd *cobra.Command, args []string) {
		accountName := args[0]

		// Load the configuration
		cfg, err := nats.LoadConfig(configKey)
		if err != nil {
			cmd.Printf("Failed to load configuration: %v\n", err)
			os.Exit(1)
		}

		// Attempt to add the new account
		jwt, updatedCfg, err := nats.AddTenant(accountName, cfg)
		if err != nil {
			cmd.Printf("Failed to create new account: %v\n", err)
			os.Exit(1)
		} else {
			cfg = updatedCfg // Update the global config with the new state

			if err := nats.SaveConfig(cfg); err != nil {
				cmd.Printf("Failed to save updated configuration: %v\n", err)
				os.Exit(1)
			}

			cmd.Printf("New account created successfully. JWT: %s\n", jwt)
		}
	},
}

func init() {
	rootCmd.AddCommand(addAccountCmd)
}
