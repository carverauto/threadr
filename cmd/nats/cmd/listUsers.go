package cmd

import (
	"os"

	"github.com/carverauto/threadr/pkg/api/nats"
	"github.com/spf13/cobra"
)

var listUsersCmd = &cobra.Command{
	Use:   "list-users [account]",
	Short: "List all users under a specified NATS account",
	Long:  `Displays a list of all users configured under a specific NATS account.`,
	Args:  cobra.ExactArgs(1), // Requires exactly one argument (account name)
	Run: func(cmd *cobra.Command, args []string) {
		accountName := args[0]

		// Load the configuration
		cfg, err := nats.LoadConfig(configKey)
		if err != nil {
			cmd.Printf("Failed to load configuration: %v\n", err)
			os.Exit(1)
		}

		// Handle listing users
		handleListUsers(cmd, cfg, accountName)
	},
}

func handleListUsers(cmd *cobra.Command, cfg *nats.Config, accountName string) {
	account, exists := cfg.Accounts[accountName]
	if !exists {
		cmd.Printf("Account '%s' not found\n", accountName)
		return
	}

	if len(account.Users) == 0 {
		cmd.Printf("No users found in account '%s'.\n", accountName)
		return
	}

	cmd.Printf("Users in account '%s':\n", accountName)
	for userName, userJWT := range account.Users {
		cmd.Printf("- %s: %s\n", userName, userJWT)
	}
}

func init() {
	rootCmd.AddCommand(listUsersCmd)
}
