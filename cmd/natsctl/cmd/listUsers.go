package cmd

import (
	"fmt"
	"github.com/carverauto/threadr/pkg/api/natsctl"
	"github.com/spf13/cobra"
)

var listUsersCmd = &cobra.Command{
	Use:   "list-users [account]",
	Short: "List all users under a specified NATS account",
	Long:  `Displays a list of all users configured under a specific NATS account.`,
	Args:  cobra.ExactArgs(1), // Requires exactly one argument (account name)
	RunE: func(cmd *cobra.Command, args []string) error {
		accountName := args[0]

		// Load the configuration using the global instanceId
		cfg, err := natsctl.LoadConfig(instanceId)
		if err != nil {
			return fmt.Errorf("failed to load configuration: %v", err)
		}

		// Handle listing users and print results
		return handleListUsers(cmd, cfg, accountName)
	},
}

func handleListUsers(cmd *cobra.Command, cfg *natsctl.Config, accountName string) error {
	account, exists := cfg.Accounts[accountName]
	if !exists {
		cmd.Printf("Account '%s' not found\n", accountName)
		return nil
	}

	if len(account.Users) == 0 {
		cmd.Printf("No users found in account '%s'.\n", accountName)
		return nil
	}

	cmd.Printf("Users in account '%s':\n", accountName)
	for userName, userJWT := range account.Users {
		cmd.Printf("- %s: %s\n", userName, userJWT)
	}
	return nil
}

func init() {
	rootCmd.AddCommand(listUsersCmd)
}
